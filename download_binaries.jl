using BinaryProvider

function get_binaries(filename,a="x86_64",b="linux",c="gnu",d="",e="gcc5",f="cxx11")
	regex_binprefix = r"bin_prefix ?=.*\n"
	prefix=abspath(joinpath(dirname(filename),"usr"))
	mkpath(prefix)
	filename = ARGS[1]
	file = open(filename)
	str = read(file,String)
	close(file)
	m_prefix=match(regex_binprefix,str)
	m_prefix == nothing && return 0
	bin_prefix=eval(Meta.parse(m_prefix.match))
	regex_binary=Regex("\\(.?\\\$bin_prefix.*$a-$b(-$c)?(-$d)?(-$e)?(-$f)?.+?\\)")
	m_binary = match(regex_binary,str)
	m_binary == nothing && return 0
	dl_info=eval(Meta.parse(m_binary.match))
	tarball_path=joinpath(prefix,"downloads",basename(dl_info[1]))
	download_verify(dl_info...,tarball_path,force=true,verbose=true)
	
	regex_finstall=r"install\(.+\)"
	m_finstall=match(regex_finstall,str)
	m_finstall == nothing && return 0
	dis_finstall = replace(m_finstall.match,"force=true"=>"force=false")
	new_str = replace(str,m_finstall.match=>dis_finstall)
	file = open(filename,"w")
	write(file,new_str)
	close(file)
end

get_binaries(ARGS[1])
