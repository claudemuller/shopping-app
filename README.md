# Shopping

A cross-platform shopping list app.

## Running a release

Download the appropriate release binary from [releases]();

## Running the app manually

```bash
flutter run -d [linux/windows/macos]
```

## Running the backend

### Via Docker

```bash
cd api/
docker buildx build -t shopping-api .
docker run 
```

### Manually

```bash
cd api/
go run ./main.go serve
```
