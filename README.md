
not a serious project

## building:

you need a version of zig with async (stage1 at the time of writing. recent compilers need a compiler flag to access stage1 i believe now)

`zig build -Dfetch`

then to run:

`./zig-out/bin/chatsoftware host [port]`

and 

`./zig-out/bin/chatsoftware connect [user name] [ip] [port]`

