# painworld
It's like rain world but was made using assembly, thus in pain.

## Specs
Start Date: October 14th
Deadline: October 20th
Language: x86 assembly, AT&T Syntax.

## Usage Guide (mac)
```bash
# Ensure docker desktop is up and running
# Notice that you can edit files under src/,
# and they will automatically sync to the docker container!

# start docker container ()
docker compose up -d
# to stop the docker container, run:
docker compose down

# get into the container
docker exec -it rain /bin/bash
# to exit the container (at the end of the development, just type in:)
exit

# Compile the script
gcc -no-pie -g -o rain rain.s

# Run the binary
./rain
```
