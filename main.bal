import ballerina/http;
import ballerina/log;
import ballerina/url;

// Type for Open Library book
type OLBook record {| 
    string[]? isbn_13; 
|};

// Types for Appwrite response
type AppwriteDoc record {| 
    record {| 
        string canonicalIsbn; 
    |} data; 
|};

type AppwriteList record {| 
    AppwriteDoc[] documents; 
|};

// --- Appwrite Configuration ---
configurable string APW_ENDPOINT = ?;
configurable string APW_PROJECT_ID = ?;
configurable string APW_API_KEY = ?;
configurable string APW_DATABASE_ID = ?;
configurable string BOOKS_COLLECTION_ID = ?;

// --- Service Definition ---
service / on new http:Listener(9090) {

    // Handles GET requests to /isbn?title=<book_title>
    resource function get isbn(string title) returns http:Response|http:InternalServerError {
        log:printInfo("Received request to find ISBN", title = title);

        // 1. Initialize HTTP client and prepare headers for Appwrite
        http:Client|http:ClientError appwriteClientResult = new (APW_ENDPOINT);
        if appwriteClientResult is http:ClientError {
            log:printError("Failed to create Appwrite client: " + appwriteClientResult.toString());
            return createNotFoundResponse("Failed to create Appwrite client");
        }
        http:Client appwriteClient = appwriteClientResult;
        map<string> appwriteHeaders = {
            "X-Appwrite-Project": APW_PROJECT_ID,
            "X-Appwrite-Key": APW_API_KEY,
            "Content-Type": "application/json"
        };
        log:printInfo("Appwrite client and headers initialized successfully.");

        // 2. Manually query Appwrite DB for an existing record
        string|url:Error encodedTitleResult = url:encode(title, "UTF-8");
        if encodedTitleResult is url:Error {
            log:printError("Failed to encode title: " + encodedTitleResult.toString());
            return createNotFoundResponse("Failed to encode title");
        }
        string encodedTitle = encodedTitleResult;
        string listUrl = string `/databases/${APW_DATABASE_ID}/collections/${BOOKS_COLLECTION_ID}/documents?queries[]=equal("title",["${encodedTitle}"])`;
        log:printInfo("Querying Appwrite for existing book...", url = listUrl);

        http:Response|error listResponse = appwriteClient->get(listUrl, headers = appwriteHeaders);
        if listResponse is error {
            log:printError("Error querying Appwrite: " + listResponse.toString());
            return createNotFoundResponse("Error querying Appwrite");
        }
        json|http:ClientError payloadResult = listResponse.getJsonPayload();
        if payloadResult is http:ClientError {
            log:printError("Error getting JSON payload from Appwrite: " + payloadResult.toString());
            return createNotFoundResponse("Error getting JSON payload from Appwrite");
        }
        json payload = payloadResult;
        // Log the raw payload for debugging
        log:printInfo("Raw Appwrite payload: " + payload.toJsonString());

        if payload is map<json> {
            map<json> payloadMap = <map<json>>payload;
            if payloadMap.hasKey("documents") {
                AppwriteList|error appwriteListResult = payload.cloneWithType(AppwriteList);
                if appwriteListResult is error {
                    log:printError("Error converting Appwrite payload: " + appwriteListResult.toString());
                    return createNotFoundResponse("Error converting Appwrite payload");
                }
                AppwriteList appwriteList = appwriteListResult;
                if appwriteList.documents.length() > 0 {
                    AppwriteDoc doc = appwriteList.documents[0];
                    string canonicalIsbn = doc.data.canonicalIsbn;
                    log:printInfo("Found ISBN in Appwrite DB", title = title, isbn = canonicalIsbn);
                    return createOkResponse(canonicalIsbn);
                }
            } else {
                log:printError("Appwrite did not return a documents list or returned an error: " + payload.toJsonString());
                return createNotFoundResponse("Appwrite did not return a documents list.");
            }
        } else {
            log:printError("Appwrite payload is not a map: " + payload.toJsonString());
            return createNotFoundResponse("Appwrite did not return a valid response.");
        }

        // 3. If not in DB, fetch from Open Library API
        log:printInfo("Book not found in Appwrite DB. Fetching from Open Library...", title = title);
        string?|error canonicalIsbnResult = findIsbnFromOpenLibrary(title);
        if canonicalIsbnResult is () {
            log:printWarn("No ISBN found in Open Library for title.", title = title);
            return createNotFoundResponse("No ISBN found for the given title.");
        } else if canonicalIsbnResult is error {
            log:printError("Error fetching from Open Library: " + canonicalIsbnResult.toString());
            return createNotFoundResponse("Error fetching from Open Library");
        } else {
            string canonicalIsbn = canonicalIsbnResult;
            // 4. Manually create the document in Appwrite via POST request
            string createUrl = string `/databases/${APW_DATABASE_ID}/collections/${BOOKS_COLLECTION_ID}/documents`;
            map<json> dataPayload = {title: title, canonicalIsbn: canonicalIsbn};
            json requestBody = {"documentId": "unique()", "data": dataPayload};

            log:printInfo("Attempting to store new book record in Appwrite...", isbn = canonicalIsbn);
            http:Response|error createResponse = appwriteClient->post(createUrl, requestBody, headers = appwriteHeaders);
            if createResponse is http:Response {
                log:printInfo("Successfully stored new book in Appwrite.", isbn = canonicalIsbn);
            } else {
                log:printError("Failed to store new book in Appwrite: " + createResponse.toString());
            }

            // 5. Return the newly found ISBN
            log:printInfo("Returning newly found ISBN from Open Library.", isbn = canonicalIsbn);
            return createOkResponse(canonicalIsbn);
        }
    }
}

// Function to call Open Library
function findIsbnFromOpenLibrary(string title) returns string?|error {
    log:printInfo("findIsbnFromOpenLibrary: Attempting to fetch from Open Library...", title = title);
    
    http:Client|http:ClientError openLibraryClientResult = new ("https://openlibrary.org");
    if openLibraryClientResult is http:ClientError {
        log:printError("findIsbnFromOpenLibrary: Failed to create HTTP client.");
        return openLibraryClientResult;
    }
    http:Client openLibraryClient = openLibraryClientResult;
    
    json|error response = openLibraryClient->get(string `/search.json?title=${title}`);
    if response is error {
        log:printError("findIsbnFromOpenLibrary: API call failed.");
        return response;
    }
    log:printInfo("findIsbnFromOpenLibrary: Successfully received response.");

    record {| json[] docs; |}|error olResponse = response.cloneWithType();
    if olResponse is error {
        log:printError("findIsbnFromOpenLibrary: Failed to parse main response structure.");
        return olResponse;
    }
    if olResponse.docs.length() == 0 { 
        log:printWarn("findIsbnFromOpenLibrary: No documents found in response.");
        return (); 
    }
    OLBook|error firstBookResult = olResponse.docs[0].cloneWithType(OLBook);
    if firstBookResult is error {
        log:printError("findIsbnFromOpenLibrary: Failed to parse book document.");
        return firstBookResult;
    }
    OLBook firstBook = firstBookResult;
    
    string[]? isbnArray = firstBook.isbn_13;
    if isbnArray is string[] {
        if isbnArray.length() > 0 {
            log:printInfo("findIsbnFromOpenLibrary: Found ISBN_13.", isbn = isbnArray[0]);
            return isbnArray[0];
        }
    }
    log:printWarn("findIsbnFromOpenLibrary: No ISBN_13 array found in the first book document.");
    return ();
}

// HTTP Response Helper Functions
function createOkResponse(string isbn) returns http:Response {
    http:Response res = new;
    res.setPayload({isbn: isbn});
    return res;
}

function createNotFoundResponse(string message) returns http:Response {
    http:Response res = new;
    res.setPayload({"error": message});
    res.statusCode = 404;
    return res;
}