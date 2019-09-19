import Pkg:activate,depots1
import Pkg.Types:Context
import Pkg.Operations:build_versions

function add_local_packages(pkgs_path,project_path)
	files=Set(readdir(pkgs_path))
	pop!(files,"Manifest.toml")
	pop!(files,"Project.toml")
    activate(project_path)
    ctx=Context()
    uuids_to_build=collect(keys(ctx.env.manifest))
    registry_path = joinpath(depots1(),"registries")
    Base.cp(joinpath(pkgs_path,pop!(files,"registries")),registry_path,force=true)
    default_path=joinpath(depots1(),"packages")
    for file in files
        	path = joinpath(pkgs_path,file)
		path_project = joinpath(default_path,file)
        	versions_pkgs = Set(readdir(path))
		versions_project = isdir(path_project) ? Set(readdir(path_project)) : Set()
		for version in setdiff(versions_pkgs,versions_project)
			path_version = joinpath(path_project,version)
			path_pkg_version = joinpath(path,version)
			mkpath(path_version)
			Base.cp(path_pkg_version,path_version,force=true)
		end
    end
    build_versions(ctx,uuids_to_build)
end

project_path = abspath(ARGS[1])
pkgs_path= abspath(ARGS[2])
add_local_packages(pkgs_path,project_path)
