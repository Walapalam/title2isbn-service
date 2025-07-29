# Title2ISBN Service

A simple, fast, and efficient caching microservice built with **Ballerina**. This service finds the canonical ISBN for a given book title by federating calls to an external API and a local database.

This project was developed as a helper service for a larger **Ebook Reader Application**.

## The Problem It Solves

In many applications, data is scattered across multiple sources. Our Ebook Reader application needs a consistent ISBN for a book, but calling external APIs for every request is slow and inefficient. This service acts as a smart caching layer to solve that problem by:

1.  Providing a single REST endpoint to get an ISBN from a book title.
2.  First checking a local Appwrite database for a cached result.
3.  If not found, fetching the data from the public Open Library API.
4.  Saving the new result back to the Appwrite database, so future requests for the same title are instantaneous.

## Architecture

This service is designed to be a component within a larger system. The typical data flow is:

`Frontend App (Ebook Reader)` → `This Ballerina Service` → `Appwrite DB (Cache) OR Open Library API (External)`

## Features

-   Built with **Ballerina**, a language optimized for network integration.
-   Provides a single, simple REST API endpoint.
-   Caches results in an **Appwrite** database to reduce latency and external API calls.
-   Includes comprehensive logging for easy debugging.

## Tech Stack

-   **Language:** Ballerina
-   **Database/Cache:** Appwrite
-   **External Data Source:** Open Library API

---

## 🚀 Setup and Configuration

To run this service locally, follow these steps.

#### 1. Prerequisites

-   Install the [Ballerina language](https://ballerina.io/downloads/).

#### 2. Clone the Repository

```sh
git clone [https://github.com/Walapalam/title2isbn-service.git](https://github.com/Walapalam/title2isbn-service.git)
cd title2isbn-service

---

### 3. Configure Credentials

This service requires credentials to connect to your Appwrite instance.

Create a file named `Config.toml` in the root of the project directory.

Copy the content below into your new `Config.toml` file and fill in the placeholder values with your actual Appwrite credentials:

```toml
APW_ENDPOINT = "<YOUR_APPWRITE_ENDPOINT_URL>"
APW_PROJECT_ID = "<YOUR_APPWRITE_PROJECT_ID>"
APW_API_KEY = "<YOUR_APPWRITE_API_KEY>"
APW_DATABASE_ID = "<YOUR_APPWRITE_DATABASE_ID>"
BOOKS_COLLECTION_ID = "<YOUR_BOOKS_COLLECTION_ID>"
```

---

### 4. Run the Service

Execute the following command in your terminal:

```sh
bal run
```

The service will start on [http://localhost:9090](http://localhost:9090).

---

## How to Use It

Send a GET request to the `/isbn` endpoint with a `title` query parameter.

**Example using cURL:**

```sh
curl -v "http://localhost:9090/isbn?title=The+Hobbit"
```

The first time you run this, you will see logs indicating it's fetching from Open Library.

The second time, the response will be much faster, and logs will show it was found in the Appwrite DB.

---

## Future Work

- [ ] Add more external data sources (e.g., Google Books API) as fallbacks.
- [ ] Containerize the service using Docker.
- [ ] Deploy the service to a cloud platform like WSO2 Choreo.