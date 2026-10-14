FROM debian:latest

RUN apt update && apt install -y build-essential gdb lldb vim nano git

WORKDIR /root/asm
