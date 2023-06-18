Param(
    [String]$Debug = 'NONE' 
)

$ErrorActionPreference = 'Stop'

$WIN_LIB_PATH = "C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0"
$APP_NAME = "main"
$OUT_FOLDER = "target"

function build(){
    $libraries = (
        "$WIN_KIT_PATH\um\x64\kernel32.Lib",
        "$WIN_KIT_PATH\um\x64\WS2_32.Lib"
    )
    
    # Compile asm to machine code
    nasm.exe -f win64 "$APP_NAME.asm" -o "$OUT_FOLDER/$APP_NAME.o"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    # Link into a valid PE
    link.exe    /nodefaultlib `
                /entry:entry `
                /subsystem:CONSOLE `
                /DEBUG:$Debug `
                /OUT:$OUT_FOLDER/$APP_NAME.exe `
                "$OUT_FOLDER/$APP_NAME.o" `
                ($libraries -join "`" `"")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function run(){
    & "$OUT_FOLDER/$APP_NAME.exe"
    if ($LASTEXITCODE -ne 0) { 
        # $LASTEXITCODE = $LASTEXITCODE | format-hex
        write-host "$APP_NAME.exe exited with code: $LASTEXITCODE"
        exit $LASTEXITCODE 
    }
}

function main(){

    New-Item -ItemType Directory $OUT_FOLDER -Force | Out-Null

    build
    run
}

main