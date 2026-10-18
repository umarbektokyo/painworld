FROM debian:latest

RUN apt update && apt install -y build-essential gdb lldb vim nano git make libncurses-dev

WORKDIR /root/painworld
