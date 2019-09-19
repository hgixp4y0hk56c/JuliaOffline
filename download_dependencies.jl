using BinaryProvider

filename = abspath(ARGS[1])
build_dir = dirname(filename)
file = open(filename)
str = read(file,String)
close(file)

regex_deps = r"https://.+\.jl"
m=collect(eachmatch(regex_deps,str))
files = String[]
for dep in m
	url = dep.match
	file = joinpath(build_dir,basename(url))
	BinaryProvider.download(url,file)
	ARGS[1] = file
	an= @eval module Anon end
	an.include("download_binaries.jl")
end

