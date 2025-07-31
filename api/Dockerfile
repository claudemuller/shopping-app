FROM golang:1.24-alpine

WORKDIR /app

COPY main.go .
COPY go.mod .
COPY go.sum .

RUN go build -o main .

EXPOSE 8090

CMD ["./main", "serve", "--http=0.0.0.0:8090"]
