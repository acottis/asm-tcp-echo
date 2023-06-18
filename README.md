# Assembly TCP Echo Server

## Requirements

Windows! This uses windows syscalls and win64 [calling convention](https://learn.microsoft.com/en-us/cpp/build/x64-calling-convention)

[nasm](https://www.nasm.us/) - Our assembler to turn *.asm files into binary

[Windows SDK](https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/) - We use windows api system calls so we need to link with the *.Lib files these function are found in

[link](https://visualstudio.microsoft.com/downloads/) - The windows link.exe application which will turn our binary into a valid Portable Executable (PE) file

## Running

The `make.ps1` builds and runs the echo server

1. Find the below in in the `make.ps1` file and update to your windows SDK path

    ```powershell
    $WIN_LIB_PATH = "C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0"
    ```

2. Run the below in a powershell window

    ```powershell
    .\make.ps1
    ```

3. Thats it!

## Did it work?

You should see the terminal hang if it is running. It is now listening on all IPv4 interfaces on port `6969` Can test with your favourite TCP client. Example using `netcat`

```bash
    echo "Testing my echo server" | nc -v 127.0.0.1 6969
```
