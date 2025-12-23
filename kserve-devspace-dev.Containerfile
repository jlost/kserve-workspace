FROM golang:1.25-bookworm

RUN mkdir /app && mkdir /.cache && chmod -R 777 /app && chmod -R 777 /.cache && chmod -R 777 /usr/local/bin
# install dlv and air
RUN go install github.com/go-delve/delve/cmd/dlv@latest
RUN go install github.com/air-verse/air@latest
