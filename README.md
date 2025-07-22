# RBDB

A relational database built on top of SQLite with integrated first-order logic capabilities.

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/chkn/rbdb.git", from: "1.0.0")
]
```

Known to work with system SQLite on macOS 26. Otherwise, you will need a SQLite built with `SQLITE_ENABLE_NORMALIZE` and a module map (see Dockerfile for an example).

## Usage

### Create database and define a predicate

```swift
import RBDB

let db = try RBDB(path: "database.db")

// Defines a `user` predicate
try db.query("CREATE TABLE user(name)")
```

### Assert facts

You can assert simple facts using either SQL or the `Formula` type:

```swift
let formula1 = Formula("user('Alice')")!
try db.assert(formula: formula1)

// The above is equivalent to:
try db.query("INSERT INTO user(name) VALUES ('Alice')")
```

### Canonicalize logically equivalent formulas

```swift
let f1 = Formula("∀x User(x)")!
let f2 = Formula("∀y User(y)")!
assert(f1.canonicalize() == f2.canonicalize())  // true
```

### SQL CLI Tool

The included `sql` command provides an interactive console:

```bash
# Interactive mode
swift run sql database.db

# Execute file
swift run sql -f script.sql database.db

# In-memory database
swift run sql
```

Example session:
```sql
sql> CREATE TABLE products (id, name, price);
sql> INSERT INTO products VALUES (1, 'Widget', 9.99);
sql> SELECT * FROM products;
┌────┬────────┬───────┐
│ id │ name   │ price │
├────┼────────┼───────┤
│ 1  │ Widget │ 9.99  │
└────┴────────┴───────┘
```

## Docker & Containerization

The provided Dockerfile creates a complete Swift build environment with RBDB dependencies, including a custom SQLite build with `SQLITE_ENABLE_NORMALIZE`. This can be used as a builder stage for containerized services.

### Building RBDB in Docker

```bash
# Build the RBDB development/build environment
docker build -t rbdb-builder .

# Run tests
docker run --rm rbdb-builder swift test

# Build release binaries
docker run --rm rbdb-builder swift build -c release
```

### Multi-stage Build for Services

To containerize a service that depends on RBDB, use a multi-stage build pattern:

```dockerfile
# Use RBDB builder as base
FROM rbdb-builder as builder

# Copy your service code
COPY your-service/ /service/
WORKDIR /service

# Build your service with RBDB dependency
RUN swift build -c release

# Production stage
FROM ubuntu:latest
RUN apt-get update && apt-get install -y \
    libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/*

# Copy custom SQLite library and your service binary
COPY --from=builder /usr/local/lib/libsqlite3.so* /usr/local/lib/
COPY --from=builder /service/.build/release/your-service /usr/local/bin/
RUN ldconfig

CMD ["your-service"]
```

This approach:
- Leverages the RBDB build environment with proper SQLite configuration
- Produces lightweight production containers with only runtime dependencies
- Maintains the custom SQLite build required for RBDB's normalized SQL feature

## Development

### Prerequisites

- Swift 6.0 or later
- System SQLite from macOS 26, or SQLite built with `SQLITE_ENABLE_NORMALIZE` (see Dockerfile)

### Building from Source

```bash
swift build
```

### Running Tests

```bash
swift test
```

### Code Formatting

The project uses `swift-format` for consistent code style:

```bash
swift format -i -r .
```

### Project Structure

```
Sources/
├── RBDB/                   # Core library
│   ├── Logic/              # First-order logic implementation
│   ├── SQLite/             # Database layer
│   ├── Utils/              # Utility functions
│   └── schema.sql          # Internal database schema
├── SQLCLITool/             # Interactive CLI tool
└── Tests/                  # Test suite
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Style

- Follow Swift naming conventions
- Use tabs for indentation
- Maintain test coverage for new features
- Try to add documentation for public APIs

## License

[Specify your license here]

