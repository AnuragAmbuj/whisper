# Whisper Plus Backend: Architecture & RESTful API Specification
**Dual-Stack Topology: Go (App Edge & Restore Gateway) + Java 21 / Spring Boot 3.3 (Store & Subscriptions Core)**  
**Edge Infrastructure: Cloudflare Global Network (Workers, R2, Hyperdrive, D1/KV, Queues, Tunnel)**  
**Identity: Mandatory Google Authentication (Gmail + Google Auth Token)**  
**Privacy: Zero Personal Profile Storage (No Names, Avatars, or Browsing History)**  
**Sync Architecture: Local-First / Google Drive (Zero Backend Reading Progress)**  
**Version:** 3.0.0 • **Status:** Approved Production Specification • **Date:** September 2026

---

## 1. System Philosophy & Scope Clarification

Whisper operates on a strict **Zero-PII, Local-First, Store-Centric** model.

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              WHISPER ECOSYSTEM TOPOLOGY                                │
├─────────────────────────┬──────────────────────────────┬───────────────────────────────┤
│ 1. Client App           │ 2. Go Edge Microservice      │ 3. Java 21 / Spring Boot Core │
│    (macOS, iOS, Android)│    (whisper-app-go)          │    (whisper-store-spring)     │
├─────────────────────────┼──────────────────────────────┼───────────────────────────────┤
│ • 100% Local Reading    │ • Forced Google Auth Validate│ • Whisper Plus Digital Store  │
│   (EPUB, PDF, CBZ, Audio│   (Gmail + Google Token)     │   (Ebooks, Comics, Audiobooks)│
│ • Realtime Progress Sync│ • Cross-Device Restore API   │ • Subscription Billing Engine │
│   via Google Drive      │   (Purchases & Plus Status)  │   (StoreKit 2 & Play Billing) │
│ • Local Annotations &   │ • Fast Cloudflare R2         │ • Media Ingestion Pipeline    │
│   SwiftData / Room DB   │   Presigned Download Links   │   (EPUB, CBZ, M4B Transcoding)│
│ • Local Apple/MLKit AI  │ • Ultra-Low Latency, Low RAM │ • Publisher Catalog & Search  │
│   (No Server Logs)      │   (~12MB resident memory)    │ • Webhook Queues (Apple/Google│
└─────────────────────────┴──────────────────────────────┴───────────────────────────────┘
```

### 1.1 What the Backend DOES NOT Do
1. **NO Reading Progress or Bookmark Storage**:
   - Reading progress (page indices, EPUB CFIs, scroll offsets, audiobook timestamps) and bookmarks are **never** stored on the Whisper backend.
   - Real-time reading synchronization across a user's devices is handled directly **client-to-Google Drive** (via the user's private Google Drive `appDataFolder`) or kept 100% local on the device.
2. **NO Personal Profile or PII Storage**:
   - The backend stores **zero** personal information: no user names, profile pictures, phone numbers, or reading telemetry.
   - The database only retains the user's verified **Gmail address**, **Google Subject ID (`sub`)**, and active **store entitlements** (purchased books and Whisper Plus subscription status).

### 1.2 What the Backend DOES Do
1. **Whisper Plus Digital Store**:
   - Sells individual digital titles: **Ebooks** (`.epub`), **Comicbooks / Manga** (`.cbz`), and **Audiobooks** (`.m4b` / `.mp3`).
   - Serves the **Whisper Plus Subscription Service**: A monthly ($4.99/mo) or yearly ($49.99/yr) plan granting all-you-can-read and all-you-can-listen access to the entire store catalogue.
2. **Cross-Device Purchase & Subscription Restoration**:
   - When a user logs in with their Gmail on a new Mac, iPad, iPhone, or Android device, the backend reconciles their past Apple In-App Purchases and Google Play purchases and restores full access to their digital library.
3. **Secure Zero-Egress Content Delivery via Cloudflare R2**:
   - Authenticated and entitled users receive ephemeral, signed URLs to download books or stream audiobooks directly from Cloudflare R2 with $0.00 egress costs.

---

## 2. Microservice Specialization: Go vs. Java / Spring Boot

The backend divides duties cleanly between two purpose-built services:

```
                               ┌────────────────────────────────────────────────────────┐
                               │                    Client Devices                      │
                               │        (macOS / iOS SwiftData • Android Room)          │
                               │   *Progress Sync: Direct to Google Drive AppData*      │
                               └───────────────────────────┬────────────────────────────┘
                                                           │ HTTPS / TLS 1.3
                                                           ▼
┌────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                Cloudflare Edge Network                                                 │
│                                                                                                                        │
│  ┌──────────────────────────┐    ┌───────────────────────────────────┐    ┌─────────────────────────────────────────┐  │
│  │  Cloudflare WAF & DDoS   │───▶│   Cloudflare API Gateway          │───▶│  Cloudflare Workers Edge Router         │  │
│  │  Turnstile Bot Defense   │    │   Edge JWT Verification           │    │  (Path Matching & Header Normalization) │  │
│  └──────────────────────────┘    └───────────────────────────────────┘    └────────────────────┬────────────────────┘  │
│                                                                                                │                       │
│                                                  Path-Based Routing Matrix                     │                       │
│               ┌────────────────────────────────────────────────────────────────────────────────┴────────┐              │
│               │ Route: /v1/auth/*, /v1/user/entitlements, /v1/purchases/restore                         │ Route:       │
│               │        /v1/catalog/*/download-url                                                       │ /v1/store/*  │
│               ▼                                                                                         │ /v1/catalog/*│
│  ┌──────────────────────────┐                                                                           │ /v1/subs/*   │
│  │   Cloudflare Tunnel A    │                                                                           ▼              │
│  │   (whisper-app-go)       │                                                             ┌──────────────────────────┐ │
│  └────────────┬─────────────┘                                                             │   Cloudflare Tunnel B    │ │
│               │                                                                           │   (whisper-store-spring) │ │
│               │                                                                           └─────────────┬────────────┘ │
│               ▼                                                                                         │              │
│  ┌──────────────────────────┐                             ┌───────────────────────────────┐             │              │
│  │ Cloudflare Workers KV/D1 │                             │      Cloudflare Queues        │             │              │
│  │ (Token Blacklist & Fast  │                             │  (StoreKit 2 / Google Play    │◀────────────┤              │
│  │  Entitlement Cache)      │                             │   Webhook Retry Buffer)       │             │              │
│  └──────────────────────────┘                             └───────────────┬───────────────┘             │              │
│                                                                           │                             ▼              │
│  ┌────────────────────────────────────────────────────────────────────────┴─────────────────────────────────────────┐ │
│  │                                          Cloudflare R2 Object Storage                                             │ │
│  │          /ebooks/*.epub  •  /comics/*.cbz  •  /audiobooks/*.m4b  •  /covers/*.webp (Zero Egress!)                 │ │
│  └───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                                         │                                                   │
                  Private VPC Ingress    ▼                                                   ▼
┌───────────────────────────────────────────────────────────────────┐ ┌──────────────────────────────────────────────────┐
│                   Go App Edge Service                             │ │       Java 21 / Spring Boot 3.3 Core             │
│                   (whisper-app-go)                                │ │       (whisper-store-spring)                     │
│                                                                   │ │                                                  │
│ • Forced Google Auth Verification (OAuth2 / OIDC)                 │ │ • Whisper Plus Catalog Management                │
│ • Whisper JWT Minting & Rotating Refresh Tokens                   │ │   (Ebooks, Comics, Audiobooks)                   │
│ • Fast Cross-Device Entitlements & Purchase Restore API           │ │ • StoreKit 2 & Google Play Subscriptions Engine  │
│ • Cloudflare R2 Presigned Download & Stream URL Generator         │ │ • Asynchronous Webhook Processor (Queues)        │
│ • Ultra-low latency, tiny memory footprint (<15MB)                │ │ • Digital Asset Ingestion & Transcoding Pipeline │
└─────────────────────────────────┬─────────────────────────────────┘ └─────────────────────────┬────────────────────────┘
                                  │                                                             │
                                  └──────────────────────────────┬──────────────────────────────┘
                                                                 ▼
                                  ┌─────────────────────────────────────────────────────────────┐
                                  │            Cloudflare Hyperdrive Connection                 │
                                  └──────────────────────────────┬──────────────────────────────┘
                                                                 ▼
                                  ┌─────────────────────────────────────────────────────────────┐
                                  │                Managed PostgreSQL 16+ Cluster               │
                                  │            (Accounts • Subscriptions • Purchases)           │
                                  └─────────────────────────────────────────────────────────────┘
```

### 2.1 Service 1: Go Microservice (`whisper-app-go`)
**Core Focus: High-Throughput App-Specific Edge Needs**
- **Forced Google Authentication**: Validates Google ID tokens via Google's token verification endpoint and Google JWKS. Mints compact, Ed25519-signed Whisper JWTs.
- **Cross-Device Entitlements & Purchase Restore Gateway**: Resolves which books and subscriptions belong to the verified Gmail, enabling instant restoration on new devices.
- **Cloudflare R2 Presigner**: Validates access permissions and generates S3-compatible presigned URLs for book downloads and audiobook streaming within <5 milliseconds.

### 2.2 Service 2: Java 21 / Spring Boot 3.3 (`whisper-store-spring`)
**Core Focus: Whisper Plus Store, Subscriptions & Asset Ingestion**
- **Store Catalog Management**: Serves the browsable catalogue of Ebooks, Comics, and Audiobooks with category facets, ratings, reviews, sample text excerpts, and audio previews.
- **Subscription Lifecycle Engine**: Verifies Apple StoreKit 2 signed JWS transactions and Google Play Billing purchases; processes asynchronous S2S notifications (`SUBSCRIBED`, `DID_RENEW`, `EXPIRED`, `REFUND`).
- **Asset Ingestion Pipeline**: Ingestion service for publisher files (validates EPUBs, extracts CBZ metadata, slices audiobook chapters, transcodes covers to WebP, and uploads to Cloudflare R2).

---

## 3. Minimal Privacy-First Database Schema (PostgreSQL 16+)

The database stores only what is legally and operationally required to verify purchases and subscriptions.

```sql
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enum Types
CREATE TYPE subscription_tier_type AS ENUM ('free', 'plus_monthly', 'plus_annual');
CREATE TYPE subscription_status_type AS ENUM ('active', 'grace_period', 'canceled', 'expired');
CREATE TYPE store_format_type AS ENUM ('epub', 'comic', 'audiobook');
CREATE TYPE billing_platform_type AS ENUM ('apple', 'google');

-- 1. Accounts Table (Strictly Minimal: Only Google Sub & Gmail)
CREATE TABLE accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    google_sub VARCHAR(255) NOT NULL UNIQUE,     -- Immutable Google User Subject ID
    email VARCHAR(255) NOT NULL UNIQUE,          -- Verified user Gmail
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Store Catalog: Ebooks, Comics, Audiobooks
CREATE TABLE catalog_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(255) NOT NULL,
    author VARCHAR(255) NOT NULL,
    narrator VARCHAR(255),                       -- For Audiobooks
    artist VARCHAR(255),                         -- For Comics
    category VARCHAR(64) NOT NULL,               -- "Sci-Fi", "Classics", "Comics", "Tech"
    summary TEXT NOT NULL,
    sample_content TEXT,                         -- Text excerpt for Ebooks
    sample_audio_r2_key TEXT,                    -- 30s preview clip for Audiobooks
    format store_format_type NOT NULL,
    page_count INT DEFAULT 0,                    -- For Ebooks and Comics
    duration_seconds INT DEFAULT 0,              -- For Audiobooks (e.g. 36000 = 10 hrs)
    price_cents INT NOT NULL DEFAULT 0,          -- e.g. 999 = $9.99 (0 if subscription only)
    is_plus_eligible BOOLEAN NOT NULL DEFAULT TRUE, -- Included in Whisper Plus subscription
    rating NUMERIC(3,2) NOT NULL DEFAULT 5.00,
    review_count INT NOT NULL DEFAULT 0,
    r2_cover_key TEXT NOT NULL,                  -- Cloudflare R2 key for WebP cover
    r2_asset_key TEXT NOT NULL,                  -- Cloudflare R2 key for .epub / .cbz / .m4b
    file_size_bytes BIGINT NOT NULL DEFAULT 0,
    asset_sha256 VARCHAR(64) NOT NULL,
    media_manifest JSONB,                        -- Audiobook cue points or Comic page manifest
    is_published BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Individual Book Purchases (Restorable on Any Device via Gmail)
CREATE TABLE purchases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    catalog_item_id UUID NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
    platform billing_platform_type NOT NULL,
    transaction_id VARCHAR(255) NOT NULL UNIQUE, -- StoreKit 2 transaction ID or Google order ID
    purchase_token TEXT,                         -- Google purchase token or Apple JWS
    purchased_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_account_item UNIQUE (account_id, catalog_item_id)
);

-- 4. Whisper Plus Subscriptions (Restorable on Any Device via Gmail)
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    platform billing_platform_type NOT NULL,
    tier subscription_tier_type NOT NULL,        -- 'plus_monthly' or 'plus_annual'
    status subscription_status_type NOT NULL,
    original_transaction_id VARCHAR(255) NOT NULL UNIQUE,
    latest_transaction_id VARCHAR(255) NOT NULL,
    purchase_date TIMESTAMPTZ NOT NULL,
    expires_date TIMESTAMPTZ NOT NULL,
    auto_renew_status BOOLEAN NOT NULL DEFAULT TRUE,
    raw_payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indices
CREATE INDEX idx_purchases_account ON purchases(account_id);
CREATE INDEX idx_subscriptions_account ON subscriptions(account_id, status);
CREATE INDEX idx_catalog_category_format ON catalog_items(category, format, is_published);
```

---

## 4. Forced Google Authentication Flow

Google Sign-In is the mandatory single sign-on mechanism across macOS, iOS, and Android. It guarantees seamless cross-device purchase restoration.

```
┌────────────────┐           ┌──────────────────┐           ┌────────────────────┐
│  Client Device │           │  Cloudflare Edge │           │   whisper-app-go   │
└───────┬────────┘           └────────┬─────────┘           └─────────┬──────────┘
        │                             │                               │
        │ 1. Native Google Auth Sign-In                               │
        │    (Retrieves ID Token)     │                               │
        │                             │                               │
        │ 2. POST /v1/auth/google     │                               │
        │    { "id_token": "..." }    │                               │
        ├────────────────────────────▶│ Forward to Go Tunnel          │
        │                             ├──────────────────────────────▶│
        │                             │                               │ 3. Validate ID Token with
        │                             │                               │    Google JWKS / Certs
        │                             │                               │ 4. Extract verified Gmail & sub
        │                             │                               │ 5. Upsert accounts table
        │                             │                               │ 6. Query active purchases & Plus sub
        │                             │                               │ 7. Mint Ed25519 Whisper JWT
        │                             │◀──────────────────────────────┤
        │◀────────────────────────────┤ 200 OK { token, entitlements }│
```

---

## 5. Cross-Device Purchase & Subscription Restoration Flow

When a user opens Whisper on a newly installed device (e.g., switches from iPhone to Android or sets up a new Mac):
1. User logs in with their **Gmail** account via Google Auth.
2. The client calls `GET /v1/purchases/restore` (or checks the response payload of `/v1/auth/google`).
3. The Go backend inspects `purchases` and `subscriptions` associated with that user's `google_sub`.
4. The response contains:
   - All `purchased_item_ids` (Ebooks, Comics, Audiobooks bought individually).
   - The active `whisper_plus` status (`is_active: true`, tier, expiration date).
5. If `whisper_plus` is active, the app immediately unlocks the **entire store catalogue** for unlimited reading and listening.

---

## 6. Cloudflare R2 Content Delivery & Streaming

All book binaries (`.epub`, `.cbz`, `.m4b`) and high-resolution cover artwork reside in private Cloudflare R2 buckets. Egress bandwidth is **100% free ($0.00)**.

### 6.1 Ephemeral Download & Streaming URL Generation
When an authenticated user wants to download an Ebook/Comic or stream an Audiobook:
1. Client requests `GET /v1/catalog/{id}/download-url`.
2. The Go microservice verifies:
   - Has the user purchased this specific `catalog_item_id`? **OR**
   - Does the user possess an active **Whisper Plus** subscription (`tier IN ('plus_monthly', 'plus_annual') AND expires_date > NOW()`)?
3. If entitled, Go uses the S3-compatible AWS SDK to generate a presigned Cloudflare R2 URL valid for **900 seconds (15 minutes)**.
4. The client downloads the file directly from Cloudflare R2 or streams audio using HTTP `Range: bytes=...` partial content headers.

---

## 7. RESTful API Specification (Exhaustive & Grouped by Service)

### 7.1 Service 1: Go Microservice (`whisper-app-go`)

#### 7.1.1 `POST /v1/auth/google` (Public)
Authenticates the user via Google Auth ID Token.
```json
// Request
{
  "id_token": "eyJhbGciOiJSUzI1NiIsImtpZCI6..."
}
```
```json
// Response (200 OK)
{
  "access_token": "eyJhbGciOiJFZERTQSI...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "account": {
    "id": "e4d2a1b9-38b2-4d5c-9c9e-8e4a6f2b0123",
    "email": "reader@gmail.com"
  },
  "entitlements": {
    "whisper_plus": {
      "is_active": true,
      "tier": "plus_annual",
      "expires_at": "2027-09-27T10:00:00Z"
    },
    "purchased_item_ids": [
      "7f8b3c40-7e3e-4b6a-bb0a-a5f1d4cb9801",
      "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e"
    ]
  }
}
```

#### 7.1.2 `GET /v1/purchases/restore` (Authenticated)
Restores purchases and subscription state across any device.
```json
// Response (200 OK)
{
  "account_email": "reader@gmail.com",
  "whisper_plus": {
    "is_active": true,
    "tier": "plus_annual",
    "status": "active",
    "expires_at": "2027-09-27T10:00:00Z",
    "auto_renew": true
  },
  "purchased_items": [
    {
      "item_id": "7f8b3c40-7e3e-4b6a-bb0a-a5f1d4cb9801",
      "title": "Project Hail Mary",
      "format": "audiobook",
      "purchased_at": "2026-09-20T14:10:00Z"
    }
  ]
}
```

#### 7.1.3 `GET /v1/catalog/{id}/download-url` (Authenticated)
Generates an ephemeral, signed R2 download link for an Ebook, Comic, or Audiobook.
```json
// Response (200 OK)
{
  "item_id": "7f8b3c40-7e3e-4b6a-bb0a-a5f1d4cb9801",
  "format": "audiobook",
  "file_size_bytes": 482910400,
  "sha256": "3a8c1f9b0e2d3c4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a",
  "download_url": "https://r2.whisper.plus/audiobooks/7f8b3c40.m4b?X-Amz-Algorithm=AWS4-HMAC-SHA256&...",
  "expires_in_seconds": 900
}
```

---

### 7.2 Service 2: Java 21 / Spring Boot Core (`whisper-store-spring`)

#### 7.2.1 `GET /v1/catalog` (Public / Authenticated)
Browses the store catalog with filtering by category and format.
```
GET /v1/catalog?format=audiobook&category=Sci-Fi&page=0&size=20
```
```json
// Response (200 OK)
{
  "items": [
    {
      "id": "7f8b3c40-7e3e-4b6a-bb0a-a5f1d4cb9801",
      "title": "Project Hail Mary",
      "author": "Andy Weir",
      "narrator": "Ray Porter",
      "category": "Sci-Fi",
      "format": "audiobook",
      "duration_seconds": 57600,
      "price_cents": 1499,
      "is_plus_eligible": true,
      "rating": 4.95,
      "review_count": 8420,
      "cover_url": "https://r2.whisper.plus/covers/7f8b3c40.webp",
      "sample_audio_url": "https://r2.whisper.plus/audiobooks/previews/7f8b3c40_sample.mp3"
    },
    {
      "id": "c1d2e3f4-5a6b-7c8d-9e0f-1a2b3c4d5e6f",
      "title": "Cyberpunk: Neon District #1",
      "author": "M. K. Vance",
      "artist": "K. Tanaka",
      "category": "Comics",
      "format": "comic",
      "page_count": 48,
      "price_cents": 499,
      "is_plus_eligible": true,
      "rating": 4.82,
      "review_count": 920,
      "cover_url": "https://r2.whisper.plus/covers/c1d2e3f4.webp",
      "sample_content": "Night in the Neon District never ends..."
    }
  ],
  "total_elements": 2,
  "total_pages": 1
}
```

#### 7.2.2 `GET /v1/catalog/{id}` (Public / Authenticated)
Retrieves deep book details, including chapter cue points for audiobooks or page manifests for comics.
```json
// Response (200 OK)
{
  "id": "7f8b3c40-7e3e-4b6a-bb0a-a5f1d4cb9801",
  "title": "Project Hail Mary",
  "author": "Andy Weir",
  "narrator": "Ray Porter",
  "format": "audiobook",
  "duration_seconds": 57600,
  "summary": "Ryland Grace is the sole survivor on a desperate, last-chance mission...",
  "media_manifest": {
    "cue_points": [
      { "chapter": 1, "title": "Chapter 1: Solitary Awakening", "start_seconds": 0.0, "duration": 1820.0 },
      { "chapter": 2, "title": "Chapter 2: The Two Robots", "start_seconds": 1820.0, "duration": 2100.0 }
    ]
  },
  "is_plus_eligible": true
}
```

#### 7.2.3 `POST /v1/subscriptions/verify-apple` (Authenticated)
Validates an Apple StoreKit 2 transaction and binds the Whisper Plus subscription to the user's Gmail.
```json
// Request
{
  "signed_transaction_jws": "eyJhbGciOiJFUzI1NiIsIng1YyI6WyJNSUlCcVRDQ0FaU...\""
}
```
```json
// Response (200 OK)
{
  "status": "success",
  "tier": "plus_annual",
  "expires_date": "2027-09-27T10:00:00Z",
  "access_granted": "all_catalog_titles"
}
```

#### 7.2.4 `POST /v1/subscriptions/verify-google` (Authenticated)
Validates a Google Play Billing purchase token and provisions Whisper Plus.
```json
// Request
{
  "product_id": "whisper_plus_annual",
  "purchase_token": "inapp-purchase-token-string"
}
```
```json
// Response (200 OK)
{
  "status": "success",
  "tier": "plus_annual",
  "expires_date": "2027-09-27T10:00:00Z",
  "access_granted": "all_catalog_titles"
}
```

#### 7.2.5 `POST /v1/webhooks/apple` & `POST /v1/webhooks/google`
Consumes Apple App Store Server Notifications v2 and Google Play RTDN events to automatically update renewal, cancellation, and expiration dates.

---

## 8. Go Implementation Blueprint (`whisper-app-go`)

```go
package main

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"google.golang.org/api/idtoken"
)

type GoogleAuthRequest struct {
	IDToken string `json:"id_token"`
}

type AuthHandler struct {
	GoogleClientID string
	Repo           AccountRepository
	TokenMinter    JWTService
}

// POST /v1/auth/google
func (h *AuthHandler) HandleGoogleAuth(w http.ResponseWriter, r *http.Request) {
	var req GoogleAuthRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid payload", http.StatusBadRequest)
		return
	}

	// 1. Force Google Auth Token Validation
	payload, err := idtoken.Validate(r.Context(), req.IDToken, h.GoogleClientID)
	if err != nil {
		http.Error(w, "Unauthorized Google Token", http.StatusUnauthorized)
		return
	}

	googleSub := payload.Subject
	email := payload.Claims["email"].(string)

	// 2. Upsert Account (Zero PII: only google_sub and verified email)
	account, err := h.Repo.UpsertAccount(r.Context(), googleSub, email)
	if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	// 3. Fetch Entitlements (Restore Purchases & Plus Status)
	entitlements, err := h.Repo.GetEntitlements(r.Context(), account.ID)
	if err != nil {
		http.Error(w, "Entitlement lookup error", http.StatusInternalServerError)
		return
	}

	// 4. Mint Ed25519 JWT
	accessToken, err := h.TokenMinter.Mint(account.ID, email, entitlements.WhisperPlus.IsActive)
	if err != nil {
		http.Error(w, "Token minting failed", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"access_token": accessToken,
		"token_type":   "Bearer",
		"expires_in":   3600,
		"account": map[string]any{
			"id":    account.ID,
			"email": email,
		},
		"entitlements": entitlements,
	})
}
```

---

## 9. Java 21 / Spring Boot 3.3 Blueprint (`whisper-store-spring`)

```java
package club.ironlattice.whisper.store.service;

import club.ironlattice.whisper.store.model.CatalogItem;
import club.ironlattice.whisper.store.repository.CatalogItemRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

@Service
@Transactional(readOnly = true)
public class CatalogQueryService {

    private final CatalogItemRepository catalogRepo;

    public CatalogQueryService(CatalogItemRepository catalogRepo) {
        this.catalogRepo = catalogRepo;
    }

    public Page<CatalogItem> listCatalog(String format, String category, Pageable pageable) {
        if (format != null && category != null) {
            return catalogRepo.findByFormatAndCategoryAndIsPublishedTrue(format, category, pageable);
        } else if (format != null) {
            return catalogRepo.findByFormatAndIsPublishedTrue(format, pageable);
        } else if (category != null) {
            return catalogRepo.findByCategoryAndIsPublishedTrue(category, pageable);
        }
        return catalogRepo.findByIsPublishedTrue(pageable);
    }

    public CatalogItem getCatalogItemDetails(UUID itemId) {
        return catalogRepo.findById(itemId)
            .orElseThrow(() -> new IllegalArgumentException("Catalog item not found: " + itemId));
    }
}
```

---

## 10. Verification & Rollout Plan

1. **Client App**:
   - Ensure native Google Auth sign-in flow is wired to `POST /v1/auth/google`.
   - Realtime reading progress continues to sync client-side via Google Drive (`GoogleDriveSyncService`) or stays local in SwiftData.
2. **Go Edge Microservice (`whisper-app-go`)**:
   - Google Auth verification & JWT issuer.
   - Entitlements lookup and purchase restore endpoint (`GET /v1/purchases/restore`).
   - S3-presigner for Cloudflare R2 downloads.
3. **Java Core Microservice (`whisper-store-spring`)**:
   - Curated store catalog for Ebooks, Comics, and Audiobooks.
   - StoreKit 2 & Google Play subscription lifecycle webhooks.
   - Publisher media ingestion pipeline.
4. **Cloudflare Global Deployment**:
   - Set up private Cloudflare R2 bucket `whisper-book-assets-prod`.
   - Configure Cloudflare Tunnel routing `/v1/auth/*`, `/v1/purchases/*`, `/v1/catalog/*/download-url` to Go and `/v1/store/*`, `/v1/catalog/*`, `/v1/subscriptions/*` to Spring Boot.
