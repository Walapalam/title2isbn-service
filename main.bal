import ballerina/http;
import ballerina/log;
import ballerina/url;

// Type for Open Library book
type OLBook record {| string[]? isbn_13; |};
// Types for Appwrite response
type AppwriteDoc record {| record {| string canonicalIsbn; |} data; |};
type AppwriteList record {| AppwriteDoc[] documents; |};

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

        // 2. Manually query Appwrite DB for an existing record
        string|url:Error encodedTitleResult = url:encode(title, "UTF-8");
        if encodedTitleResult is url:Error {
            log:printError("Failed to encode title: " + encodedTitleResult.toString());
            return createNotFoundResponse("Failed to encode title");
        }
        string encodedTitle = encodedTitleResult;
        string listUrl = string `/databases/${APW_DATABASE_ID}/collections/${BOOKS_COLLECTION_ID}/documents?queries[]=equal("title",["${encodedTitle}"])`;

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
        AppwriteList|error appwriteListResult = payload.cloneWithType(AppwriteList);
        if appwriteListResult is error {
            log:printError("Error converting Appwrite payload: " + appwriteListResult.toString());
            return createNotFoundResponse("Error converting Appwrite payload");
        }
        AppwriteList appwriteList = appwriteListResult;
        if appwriteList.documents.length() > 0 {
            AppwriteDoc|error docResult = appwriteList.documents[0].cloneWithType(AppwriteDoc);
            if docResult is error {
                log:printError("Error converting Appwrite document: " + docResult.toString());
                return createNotFoundResponse("Error converting Appwrite document");
            }
            AppwriteDoc doc = docResult;
            string canonicalIsbn = doc.data.canonicalIsbn;
            log:printInfo("Found ISBN in Appwrite DB", title = title, isbn = canonicalIsbn);
            return createOkResponse(canonicalIsbn);
        }

        // 3. If not in DB, fetch from Open Library API
        log:printInfo("Book not found in DB, fetching from Open Library", title = title);
        (string|error)? canonicalIsbnResult = findIsbnFromOpenLibrary(title);
        if canonicalIsbnResult is () {
            log:printWarn("No ISBN found in Open Library", title = title);
        } else if canonicalIsbnResult is error {
            log:printError("Error fetching from Open Library: " + canonicalIsbnResult.toString());
            return createNotFoundResponse("Error fetching from Open Library");
        } else if canonicalIsbnResult is string {
            string canonicalIsbn = canonicalIsbnResult;
            // 4. Manually create the document in Appwrite via POST request
            string createUrl = string `/databases/${APW_DATABASE_ID}/collections/${BOOKS_COLLECTION_ID}/documents`;
            map<json> dataPayload = {title: title, canonicalIsbn: canonicalIsbn};
            json requestBody = {"documentId": "unique()", "data": dataPayload};

            http:Response|error createResponse = appwriteClient->post(createUrl, requestBody, headers = appwriteHeaders);
            if createResponse is http:Response {
                log:printInfo("Successfully stored new book in Appwrite", isbn = canonicalIsbn);
            } else {
                log:printError("Failed to store new book in Appwrite: " + createResponse.toString());
            }

            // 5. Return the newly found ISBN
            return createOkResponse(canonicalIsbn);
        }
    }
}

// Function to call Open Library (unchanged)
function findIsbnFromOpenLibrary(string title) returns string?|error {
    http:Client openLibraryClient = check new ("https://openlibrary.org");
    json response = check openLibraryClient->get(string `/search.json?title=${title}`);
    record {| json[] docs; |} olResponse = check response.cloneWithType();
    if olResponse.docs.length() == 0 { return (); }
    OLBook firstBook = <OLBook>olResponse.docs[0];
    if firstBook.isbn_13 is string[] {
        string[] isbnArr = <string[]>firstBook.isbn_13;
        if isbnArr.length() > 0 {
            return isbnArr[0];
        }
    }
    return ();
}

// HTTP Response Helper Functions (unchanged)
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