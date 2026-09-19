using SHA

# 性能探针只比较同一UTF-8字节的传递方式，不求解、不改写输入；不作为优化算法速度证据。
sha256("warmup")
sha256(UInt8[0x01])
sha256(IOBuffer("warmup"))
for n in (4096, 16384, 65536, 262144, 1048576)
    s=repeat("质量守恒", cld(n, 12))
    t=time_ns()
    a=sha256(s)
    string_sec=(time_ns()-t)/1e9
    t=time_ns()
    b=sha256(Vector{UInt8}(codeunits(s)))
    bytes_sec=(time_ns()-t)/1e9
    t=time_ns()
    c=sha256(IOBuffer(s))
    stream_sec=(time_ns()-t)/1e9
    a==b==c || error("SHA字节载体改变了摘要")
    println(
        "bytes=",
        ncodeunits(s),
        " string_sec=",
        string_sec,
        " bytes_sec=",
        bytes_sec,
        " stream_sec=",
        stream_sec,
        " equal=true",
    )
    flush(stdout)
end
if !isempty(ARGS)
    path=only(ARGS)
    data=read(path, String)
    t=time_ns()
    a=bytes2hex(sha256(IOBuffer(data)))
    elapsed=(time_ns()-t)/1e9
    b=bytes2hex(sha256(read(path)))
    a==b || error("流式摘要与原文件字节不同")
    println(
        "saved_result bytes=",
        ncodeunits(data),
        " stream_sec=",
        elapsed,
        " equal=true hash=",
        a,
    )
end
