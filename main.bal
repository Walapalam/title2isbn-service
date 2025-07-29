import ballerina/http;
import ballerina/log;
// No need to import config in Ballerina 2201.x+

// BookResult type must be at module level
type BookResult record {
    string isbn;
    string author;
    string source;
};

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
        // 1. Prepare Appwrite HTTP client and headers
        http:Client appwriteClient = check new (APW_ENDPOINT);
        map<string> headers = {
            "X-Appwrite-Project": APW_PROJECT_ID,
            "X-Appwrite-Key": APW_API_KEY,
            "Content-Type": "application/json"
        };

        // 2. Query Appwrite DB for an existing record
        string listUrl = string `/databases/${APW_DATABASE_ID}/collections/${BOOKS_COLLECTION_ID}/documents?queries[]=equal("title","${title}")`;
        string? isbnAppwrite = ();
        string? authorAppwrite = ();
        var listResp = appwriteClient->get(listUrl, headers = headers);
        if listResp is http:Response {
            json|error listPayload = listResp.getJsonPayload();
            if listPayload is json {
                json[] docs = [];
                if "documents" in listPayload && listPayload["documents"] is json[] {
                    docs = <json[]>listPayload["documents"];
                }
                if docs.length() > 0 {
                    json bookData = docs[0];
                    if "isbn" in bookData && bookData["isbn"] is string && "author" in bookData && bookData["author"] is string {
                        isbnAppwrite = <string>bookData["isbn"];
                        authorAppwrite = <string>bookData["author"];
                        log:printInfo("Found ISBN in Appwrite DB", title = title, isbn = isbnAppwrite, author = authorAppwrite);
                    }
                }
            }
        } else {
            log:printError("Error querying Appwrite", err = listResp);
        }

        // 3. Query Open Library API
        http:Client openLibraryClient = check new ("https://openlibrary.org");
        string? isbnOpenLib = ();
        string? authorOpenLib = ();
        var olResp = openLibraryClient->get(string `/search.json?title=${title}`);
        if olResp is http:Response {
            json|error olPayload = olResp.getJsonPayload();
            if olPayload is json {
                json[] olDocs = [];
                if "docs" in olPayload && olPayload["docs"] is json[] {
                    olDocs = <json[]>olPayload["docs"];
                }
                if olDocs.length() > 0 {
                    json olBook = olDocs[0];
                    if "isbn" in olBook && olBook["isbn"] is json[] {
                        json[] isbns = <json[]>olBook["isbn"];
                        if isbns.length() > 0 {
                            isbnOpenLib = isbns[0].toString();
                        }
                    }
                    if "author_name" in olBook && olBook["author_name"] is json[] {
                        json[] authors = <json[]>olBook["author_name"];
                        if authors.length() > 0 {
                            authorOpenLib = authors[0].toString();
                        }
                    }
                }
            }
        }

        // 4. Query Google Books API
        http:Client googleBooksClient = check new ("https://www.googleapis.com");
        string? isbnGoogle = ();
        string? authorGoogle = ();
        string googleUrl = string `/books/v1/volumes?q=intitle:${title}`;
        var gbResp = googleBooksClient->get(googleUrl);
        if gbResp is http:Response {
            json|error gbPayload = gbResp.getJsonPayload();
            if gbPayload is json {
                json[] gbItems = [];
                if "items" in gbPayload && gbPayload["items"] is json[] {
                    gbItems = <json[]>gbPayload["items"];
                }
                if gbItems.length() > 0 {
                    json gbBook = gbItems[0];
                    if "volumeInfo" in gbBook && gbBook["volumeInfo"] is json {
                        json volumeInfo = <json>gbBook["volumeInfo"];
                        if "industryIdentifiers" in volumeInfo && volumeInfo["industryIdentifiers"] is json[] {
                            json[] ids = <json[]>volumeInfo["industryIdentifiers"];
                            foreach var id in ids {
                                if id is json && "type" in id && id["type"] is string && id["type"] == "ISBN_13" && "identifier" in id && id["identifier"] is string {
                                    isbnGoogle = <string>id["identifier"];
                                    break;
                                }
                            }
                        }
                        if "authors" in volumeInfo && volumeInfo["authors"] is json[] {
                            json[] authors = <json[]>volumeInfo["authors"];
                            if authors.length() > 0 {
                                authorGoogle = authors[0].toString();
                            }
                        }
                    }
                }
            }
        }

        // 5. Pick the most prominent ISBN by author match, or random if all are different
        BookResult[] found = [];
        if isbnAppwrite is string && authorAppwrite is string {
            found.push({isbn: isbnAppwrite, author: authorAppwrite, source: "appwrite"});
        }
        if isbnOpenLib is string && authorOpenLib is string {
            found.push({isbn: isbnOpenLib, author: authorOpenLib, source: "openlibrary"});
        }
        if isbnGoogle is string && authorGoogle is string {
            found.push({isbn: isbnGoogle, author: authorGoogle, source: "google"});
        }

        if found.length() == 0 {
            log:printWarn("Could not find an ISBN for title in any source", title = title);
            return createNotFoundResponse("No ISBN found for the given title.");
        }

        // Try to find the most common author
        map<int> authorCounts = {};
        foreach var b in found {
            authorCounts[b.author] = (authorCounts.hasKey(b.author) ? authorCounts[b.author] + 1 : 1);
        }
        int maxCount = 0;
        string prominentAuthor = "";
        foreach var [author, count] in authorCounts.entries() {
            if count > maxCount {
                maxCount = count;
                prominentAuthor = author;
            }
        }
        BookResult prominent = found[0];
        if maxCount > 1 {
            // Pick the ISBN with the most common author
            foreach var b in found {
                if b.author == prominentAuthor {
                    prominent = b;
                    break;
                }
            }
        }
        log:printInfo("Returning prominent ISBN", isbn = prominent.isbn, author = prominent.author, source = prominent.source);
        return createOkResponseWithAuthor(prominent.isbn, prominent.author);
    }
}

// --- Helper Functions for HTTP Responses ---
function createOkResponseWithAuthor(string isbn, string author) returns http:Response {
    http:Response res = new;
    res.setPayload({isbn: isbn, author: author});
    res.statusCode = 200; // OK
    return res;
}

function createNotFoundResponse(string message) returns http:Response {
    http:Response res = new;
    res.setPayload({error: message});
    res.statusCode = 404; // Not Found
    return res;
}
