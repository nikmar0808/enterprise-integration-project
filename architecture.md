# Enterprise Integration Architecture Specification

**Document Ref:** SD-EAI-001
**System Scope:** Smart-Meter Data Bridge Ingestion Pipeline 

## What Are We Trying to Build? (The Big Picture)

We are building a software bridge that safely passes electrical grid data from an ingestion point to an analysis engine.

* **The Python Piece (The Receiver/Analyzer):** Built with a tool called FastAPI. Python is used because it handles data transformation, manipulation, and analysis incredibly fast and with very few lines of code. It will receive data, inspect it to ensure it is valid, and summarize it.

* **The Java Piece (The Collector/Dispatcher):** Built with a tool called Spring Boot. Java is used because it is rock-solid for enterprise stability, handling multithreading, connection timeouts, network drops, and automated background schedules. It acts as the gatekeeper that collects raw inputs from the outside world and guarantees they are safely sent to Python.

## Runtime Environment Virtualization

**Target Environment:** Private / Local-Virtualised (On-Premises Equivalent)
**What it means:** Historically, you provisioned a heavy Virtual Machine (VM) via VMware, allocating specific CPU cores, RAM, and a full guest Operating System (like RedHat Linux). This took hours or days.
**What we are doing instead:** We are going to use Docker Containers. A container is a "micro-VM." It does not allocate dedicated hardware or boot a heavy guest OS. Instead, it shares your laptop's existing operating system kernel but carves out a tiny, isolated box for your app to run in.
**Current Status:** Once the code is ready, a 5-line configuration text file (Dockerfile) will automatically turn our code into one of these lightweight containers.

* **Application Layer:** The Java gateway and Python validation pipeline run as fully containerized micro-machines, completely unaware of your laptop's local configuration.

* **Database Isolation:** An isolated instance of an enterprise database engine (e.g., PostgreSQL) will spin up instantly as a separate, background container node, mapping storage volumes locally to retain state safely.

* **Test Data Ingestion Mechanics:** Mock data streams mimicking smart-meter telemetry records are programmatically mounted into the Java ingestion service via local test scripts. This replicates bulk telemetry files dropping onto private network file systems.


## 1. Professional Development Environment Topography

Modern professional setups decouple developers' laptops from volatile system-wide dependencies. The core objective is **environment reproducibility**—if a developer's machine encounters a catastrophic failure, they should be fully operational on alternative hardware within an hour. 

+--------------------------------------------------------------------------+

|                        LOCAL OPERATING SYSTEM (HOST)                     |
|  [VS Code Editor] <--- Extensions: Python, Extension Pack for Java       |
+--------------------------------------------------------------------------+
                                    │
       ┌────────────────────────────┴────────────────────────────┐
       ▼                                                         ▼
+──────────────────────────────────+      +──────────────────────────────────+

|      PYTHON WORKSPACE ISOLATION  |      |       JAVA WORKSPACE ISOLATION   |
| Path: \02-python-...             |      | Path: \01-java-...               |
| Sandbox Engine: .venv directory  |      | Build/Spec Engine: Maven (POM)   |
| Scope: Pinned packages via pip   |      | Scope: Portable JAR dependencies |
+──────────────────────────────────+      +──────────────────────────────────+

### Python Transfomration and Analysis Layer

### Sandbox Engine: .venv and Pinned Packages via pip
**What it means:** Python installs libraries globally by default. If Project A needs FastAPI version 1.0 and Project B needs FastAPI version 2.0, they will overwrite each other and crash.

* **.venv (Virtual Environment):** This is a literal folder created inside your project. When activated, it forces Python to install third-party libraries only inside that folder.

* **Pinned Packages:** Writing fastapi==0.115.6 in requirements.txt is "pinning." It means we lock the exact version. This ensures that even if the authors of FastAPI update their code tomorrow, your project remains stable and never breaks due to unexpected external changes.

* **pip:** This is simply the command-line tool (Python's package manager) that reads your text file and downloads those libraries into your .venv folder.

* **IDE Context Integration:** VS Code acts strictly as an omni-channel editor panel. Language-specific intelligence is managed by mounting extensions into specific subdirectory contexts.

* **Runtime Isolation Logic:**
  1. **Python:** Uses venv to capture local third-party wheels directly inside an un-tracked folder structure.
  2. **Java:** Eliminates the pre-installed application server constraint entirely. Dependencies are specified via Maven declarations, compiling directly into an executable target wrapper carrying an embedded servlet server engine.

### Java Ingestion Layer

### Build/Spec Engine: Maven (POM) and Portable JAR Dependencies
**What it means:** In the legacy J2EE/Java EE era, if your Java project needed external libraries, you had to manually download .jar files from various websites and copy them into a lib folder.

* **Maven:** This is the industry-standard project coordinator for Java. Instead of downloading files manually, you create a single XML file called a pom.xml (Project Object Model). You type the name of the library you want, and Maven automatically downloads it, handles its security patches, and links it to your code.

* **Portable JAR:** Modern Java compiles your code and its web server into one single, executable file (a .jar file). You can copy this single file to any server on earth, type java -jar app.jar, and it boots instantly.

* **Spring Boot 3.x / 4.x:** A lightweight container that completely strips out legacy J2EE application server overhead. It manages component lifecycles, configuration injection, and background task schedules.

* **RestClient / WebClient:** Modern HTTP communication clients that incorporate connection pools and built-in failure recovery mechanisms.Utilized inside IntegrationClient with an attached 3x exponential backoff circuit loop.

 (https://goregulus.com/cra-basics/spring-boot-versions/)

## 2. Distributed Version Control & Promotion Pipelines (Git / GitHub)

In a decentralized Git architecture, changes are treated as transactional database mutations ledgered locally before being replicated upstream. 

### Bulk Actions and Partial Retrieval

* **Bulk Commits:** Professional developers do *not* blindly run git add . to capture massive sets of changes without validation. The command git add -p (patch-add) is used to review every code change line-by-line, splitting modifications into isolated logic packets.

* **Granular Extraction (git checkout):** Git captures entire object trees. To pull single files or directories without switching branches or executing a full downstream update, run: 

git checkout <source_branch_name> -- path/to/target_file.py

### Branching Topology: GitFlow Framework

#### GitFlow & Environment Synchronization (Dev ──> Stage ──> Prod)
* **The Core Concept:** You never want a developer writing code directly on a live production system.

* **The Branching Blueprint:** In Git, your code line can split into multiple parallel timelines (branches):
  1. **main:** The sacred timeline. It holds the exact code currently running in production.
  2. **develop:** The testing timeline. It holds code currently being reviewed for deployment.
  3. **feature/add-meter:** An isolated workspace where a developer experiments with a new feature without affecting anyone else.

* **How Promotion Works:** When a feature is finished, you submit a pull request to merge it into develop. An automated script builds a Docker image of that code and launches it in a Stage environment (a replica server used for QA testing). Once QA signs off, that exact same Docker container is pointed to the Production environment databases. You shift code upward by moving pointers, not by rewriting code.

For robust enterprise deployments, a strict **GitFlow branching structure** maintains separation between production states, active verification testing environments, and unstable developer features.

 (https://medium.com/@dmosyan/version-control-branching-strategies-e68e8d5ef1e0)

[Feature Branch] ───────────────┐ (Short-lived developer feature workspaces)
                               ▼ Merge Request / Code Review
[Develop Branch] ───────────────┴─────────────────► Staged to [STAGE ENVIRONMENT]
                               │
                               ▼ Release Hardening
[Main/Prod Branch] ───────────────────────────────► Synchronized to [PROD ENVIRONMENT]

**The "When" Checklist (The Production Gate)**
Before touching main, an architect verifies these three constraints:
  1. End-to-End Success: The code runs flawlessly from the ingestion point to the analysis storage without errors.
  2. Green Test Suites: All automated units and integration tests (pytest) pass cleanly with zero structural failures.
  3. Pristine State: Your active local develop branch is completely committed and pushed up to GitHub with a clean transaction ledger.

When all checks pass, you execute this sequence in your VS Code terminal to safely merge your staging code timeline upward into your production timeline:

  * **Step 1:** Switch to the Production Track
    Move your active terminal focus out of develop and step onto the sacred main branch:
      git checkout main
  * **Step 2:** Pull the Latest Remote Code
    Before adding anything new, ensure your local laptop copy of main is perfectly synchronized with whatever sits on GitHub:
      git pull origin main
  * **Step 3:** Execute the Merge Transaction
    Instruct Git to pull your completed history timeline from develop and weave it directly into main:
      git merge develop
    What happens under the hood: Git matches the commit ledgers, notices that develop is ahead of main, and safely slides all your new configuration, services, and test files into the production branch timeline.
  * **Step 4:** Replicate Upstream to the Cloud
    Right now, this merge only exists on your local laptop. To make it official and update your public GitHub repository production view, push the changes up:
      git push origin main
  * **Step 5:** Return to Your Workspace
    Once the deployment is complete, immediately step back off the production track and return to your safe testing sandbox to continue working on your next features:
      git checkout develop

A Standard Professional Rule
  Once you set up a team or work for enterprise clients, they will often add a security block on GitHub that completely prevents developers from using
    git push origin main
  directly from their laptops.
  Instead, you use the browser interface to create a Pull Request (PR). This forces the code to go through an automated pipeline that runs your test suite (pytest) in the cloud and requires another senior engineer to review your code before it can slide into main.

### Environment Synchronization Matrix (Dev <---> Stage <---> Prod)

**Code never migrates between environments by copying files manually.** Environment progression relies entirely on the **Immutable Artifact Concept**: 

* **Code Hardening:** A developer merges code from a feature branch into develop. This triggers an automated pipeline that builds a singular compiled application container image.

* **Immutable Promotion:** That exact application container image is shipped to the **Stage Environment** for testing. Once approved, the *identical binary package* is pointed to production databases.

* **Environment Divergence Management:** Differences between Dev, Stage, and Prod environments (such as database credentials, target URLs, or encryption strengths) are **never hardcoded**. They are injected externally at runtime using local system environment variables.

## 3. Deployment, Orchestration, & Test Data Topography

**What it means:** Running multiple containers (Java, Python, Database) means they need to talk to each other. Orchestration is the network map connecting them. We will use a tool called Docker Compose (a simple YAML file) that tells your laptop: "Spin up Container A, Container B, and Database C, and put them on a secure, private virtual internal network."

**Test Data:** We don't have real smart-meter feeds. We will create a local folder with mock JSON files (simulating meter readings). Our Java program will read these files off your disk and pump them through the API pipeline to test the architecture under load.

To eliminate infrastructure provisioning costs and cloud dependencies, the local machine is treated as a fully virtualized, multi-node enterprise environment utilizing **Docker Engines**. 

+--------------------------------------------------------------------------+

|                       DOCKER RUNTIME ARCHITECTURE                        |
|                                                                          |
|  ┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐|
|  │ CONTAINER 1      │      │ CONTAINER 2      │      │ CONTAINER 3      │|
|  │ Java Ingestion   │ ───> │ Python Engine    │ ───> │ PostgreSQL DB    │|
|  │ (Spring Boot)    │      │ (FastAPI App)    │      │ (Local Storage)  │|
|  └──────────────────┘      └──────────────────┘      └──────────────────┘|
+--------------------------------------------------------------------------+
                                    ▲
                                    │ Volume Mounting
                       ┌────────────┴────────────┐
                       │   LOCAL HOST STORAGE    │
                       │   \test-payloads\*.json │
                       +-------------------------+

## 4. Middleware & Framework Component Directory

The chosen stack utilizes high-throughput, lightweight, and open-source enterprise libraries.

 (https://aws.plainenglish.io/best-python-fastapi-production-tools-2026-complete-developer-guide-47b97be96d8b)

### Python Transformation Layer & Database Layer

Our goal is to write a Python layer that performs three roles:

* **Data Parser:** It will read XML files safely without causing memory leaks on an on-premises machine, parse its fields using the standard library module xml.etree.ElementTree and run them against your strict Pydantic schema validation rules.

* **Data Transformer/Translator:** It will map legacy naming fields to standard data objects and output a clean JSON data string.

* **Data Persistence/Analysis:** It will write/read data to a database and perform analytical operations on it

* **Key Technology used:**
  1. **FastAPI:** A modern asynchronous server framework that routes inbound network traffic via high-performance ASGI loops.
  2. **Pydantic v2:** An ultra-fast data validation library. Its core validation engine is written in Rust, giving it an elite processing speed boost across single-meter data collection reading arrays. It handles automatic ISO-8601 string-to-datetime object serialization natively.
  3. **SQLAlchemy 2.x:** The industry-standard Python Object-Relational Mapper. Manages connection pooling parameters (pool_size=10, max_overflow=20) and ensures safe connection lifecycles via automated pre-ping queries.
  4. **Psycopg 3:** High-performance, modern native driver that interfaces Python directly with the background PostgreSQL engine over the postgresql+psycopg:// connection URL pattern, bypassing legacy psycopg2 compilation dependencies.

### Java Ingestion Gateway Core Layer

* **Key Technology used:**
  1. **Jakarta Validation Engine:** Hooked natively onto inbound Java parameters via @Valid annotations to drop syntactically broken structures before internal dispatch mechanisms execute.
  2. **Jackson Conversion Aliases:** Implements mapping annotations (@JsonProperty("meter_id"), @JsonProperty("kwh_value")) across native Java 21 Records to ensure absolute syntax compatibility between camelCase compilation files and snake_case system payloads.

### Swagger Playground
**What it is:** In the past, to test an API, you had to write a separate script or use heavy client tools like SoapUI.

**The Playground:** FastAPI automatically generates a beautiful, interactive website out of your code. When you navigate to http://127.0.0.1:8000/docs, you see a clean visual UI listing all your API ports. You can click on an endpoint, view the exact expected JSON data layout, click "Try it out," modify values, and fire requests directly to your running Python engine in real-time.

* **FastAPI:** A modern asynchronous server framework that routes inbound network traffic via high-performance ASGI loops. It automatically serializes incoming JSON structures directly into functional language variables.

* **Pydantic:** An ultra-fast data validation library. Since version 2, its core validation engine (pydantic-core) is written in Rust, giving it a major speed boost over the pure-Python implementation. It parses data structures, verifies parameters, and enforces data types before the application logic processes the information.

* **Uvicorn:** A lightning-fast, concurrent HTTP network execution loop designed to handle high volumes of parallel system connections.

 (https://www.zestminds.com/blog/fastapi-requirements-setup-guide-2025/)

## 5. API Endpoint Security Architecture

### Do we need certificates?
**For our local setup:** No, you do not need to install complex corporate SSL certificates on your laptop right now. Managing local certificates can cause errors that derail learning.

**How we handle it:** We will design the code to accept API Security Tokens (a lightweight cryptographic string passed in the header of the web request). This simulates enterprise security validation architecture without requiring the setup of a localized Certificate Authority.

In highly regulated utility environments, all open connection ports must be protected to prevent unauthorized lateral movement inside internal networks. 

       [ INBOUND CLIENT REQUEST ]
                   │
                   ▼
┌──────────────────────────────────────┐
│       MUTUAL TLS AUTHENTICATION      │  <-- Cryptographic transport handshake validation
└──────────────────┬───────────────────┘
                   │ Pass Verification
                   ▼
┌──────────────────────────────────────┐
│        JWT AUTHORIZATION LAYER       │  <-- Access token structural validity audit
└──────────────────┬───────────────────┘
                   │ Valid Token
                   ▼
┌──────────────────────────────────────┐
│       ENTERPRISE APPLICATION LOGIC   │  <-- Core transactional execution engine
└──────────────────────────────────────┘

* **Transport Layer Security (Mutual TLS / mTLS):** Both systems present a cryptographic x509 certificate during the initial connection handshake. The client validates the server, and the server validates the client, instantly dropping any connection request that lacks a trusted corporate certificate authority signature.

* **Bearer Token Authorization (JWT - JSON Web Tokens):** In addition to network-level certificates, requests must pass an authorization header containing an encrypted identity string. The integration layers validate this token locally via public keys to verify the sender has explicit rights to access the interface.

* **Payload Sanitization Enforcement:** To prevent injection attacks on downstream internal databases, Pydantic and Spring Boot auto-sanitize structural inputs, dropping payloads that contain illicit control scripts or unexpected structure mutations.

## 6. Production Environment & Layered Topography

Modern professional setups decouple packages into clear, isolated layers to enforce the architectural principle of the Separation of Concerns.
C:\enterprise-integration-project\
├── docker-compose.yml    --> Multi-node system virtualization file mapping ports, system environment secrets, and volumes.
└── stream_telemetry.py   --> Python Code to flood your ingestion gateway with hundreds of mock readings to test stability under load

C:\enterprise-integration-project\02-python-transformation-api\
├── Dockerfile            --> Blueprint to containerize your FastAPI engine.
├── app/
│   ├── config.py         --> Centralized Environment Variable & File Config (Pydantic Settings)
│   ├── main.py           --> Service Bootstrap Engine & Hook Initializer
│   │
│   ├── schemas/          --> CONTRACT LAYER (Data Transfer Objects)
│   │     └── meter.py    --> Strict Type & Range Boundary Constraints (Pydantic Models)
│   │
│   ├── api/              --> CONTROLLER LAYER (Network Router Gateways)
│   │     └── transform.py--> Inbound REST Ingress & Token Security Interception
│   │
│   │── services/         --> CORE SERVICE LAYER (Data Translation Pipelines)
│   │      └── transformer.py -> Disk-In-Motion XML-to-JSON Structural Transformer
│   ├── database/
│   │   ├── connection.py    --> STORAGE CONFIG: Core connection engine & pool session loop
│   │   └── models.py        --> SCHEMA TIER: Relational table record data maps
│   └── schemas/
│       └── meter.py         --> VALIDATION LAYER: Pure Pydantic model contract definitions
└── tests/
    └── test_integration.py -> AUTOMATED TESTING LAYER (Pytest HTTP Client Simulation)

C:\enterprise-integration-project\01-java-ingestion-service\
├── Dockerfile                      --> Multi-stage build manifest optimizing your portable runtime JAR.
├── src/main/java/com/utility/ingest/
│   ├── IngestionApplication.java   --> System Bootstrap Engine & Health Endpoint Check
│   ├── IngestionController.java    --> CONTROLLER LAYER: Inbound HTTP REST Ingress routing
│   ├── IntegrationClient.java      --> CLIENT LAYER: Modern RestClient with 3x retry loop
│   └── MeterReading.java / SmartMeterPayload.java --> CONTRACT LAYER: Immutable Java 21 Records
└── src/main/resources/
    └── application.properties     --> Infrastructure topology parameters (Port 8081)

## 7. Ingress Security & Data Validation Topology

In highly regulated utility environments, ports must be heavily guarded to prevent arbitrary lateral data flooding on internal data center networks.

[ INBOUND CLIENT REQUEST ]
                   │
                   ▼
┌──────────────────────────────────────┐
│     HEADER TOKEN AUTHENTICATION      │  <-- Cryptographic token guard check
│      (X-Utility-Grid-Token)          │      Verifies against env/secret files
└──────────────────┬───────────────────┘
                   │ Pass Token Audit
                   ▼
┌──────────────────────────────────────┐
│       CONTRACT SCHEMA VALIDATION     │  <-- Pydantic boundary interception
│         (422 Error Handlers)         │      Enforces validation limits (e.g., kwh_value > 0)
└──────────────────┬───────────────────┘
                   │ Valid Payload Data
                   ▼
┌──────────────────────────────────────┐
│      ENTERPRISE APPLICATION LOGIC    │  <-- Rounded processing calculations
└──────────────────────────────────────┘

* Behavioral Verification Matrix:
  1. **Security Gate Audit:** Validates that incoming network packets missing the token header or carrying a malformed token are rejected via HTTP 401 Unauthorized responses before logic execution.
  2. **Contract Ingestion Validation:** Confirms that a mathematically sound payload maps seamlessly into metrics frames with an HTTP 200 OK return.
  3. **Constraint Enforcement:** Verifies that payloads carrying boundary violations (such as negative energy records or brief identifier tags) trigger an explicit HTTP 422 Unprocessable Entity state.


## 8. Automated Verification & Testing Architecture
To prevent future configuration changes, environment migrations, or library updates from breaking the interface, an automated execution test layer sits completely decoupled from production runtimes.

* **Engine:** pytest combined with FastAPI's native mock test class called TestClient. It hooks into your main class instance and allows your testing engine to fire simulated HTTP requests at your endpoints without actually spinning up a live network port thread.

## 9. Multi-container Docker Compose infrastructure stack to build your local virtualized network topology

This orchestration layer lets your Java gateway, Python validation engine, and an isolated PostgreSQL database communicate seamlessly using internal container domain names.

* Component Directory Blueprint
We will drop these configurations directly into your master project root:
  1. **Python Validation Engine Dockerfile:** C:\enterprise-integration-project\02-python-transformation-api\Dockerfile: Blueprint to containerize your FastAPI engine.
  2. **Java Ingestion Gateway Multi-Stage Dockerfile:** C:\enterprise-integration-project\01-java-ingestion-service\Dockerfile: Multi-stage build manifest optimizing your portable runtime JAR.
  3. **Comprehensive Master Orchestration Architecture:** C:\enterprise-integration-project\docker-compose.yml: Multi-node system virtualization file mapping ports, system environment secrets, and volumes.

