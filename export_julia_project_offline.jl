import Pkg.Types
import Pkg.Types:Context,PackageSpec,project_deps_resolve!,registry_resolve!,stdlib_resolve!,ensure_resolved,manifest_info,pkgerror,printpkgstyle,is_stdlib,write_env,projectfile_path
import Pkg:activate
import Pkg.Operations
import Pkg.Operations:source_path,download_source,load_urls,is_dep,update_package_add,load_direct_deps!,check_registered,resolve_versions!,update_manifest!,tracking_registered_version,install_archive,install_git,set_readonly,find_installed,gen_build_code,build_versions,dependency_order_uuids,buildfile,project_rel_path,backwards_compat_for_build,sandbox,testdir,builddir
import Pkg.BinaryProvider
import Pkg:depots1
using UUIDs
import LibGit2

join_external_source(path_to_external,path_to_source) = joinpath(path_to_external,splitpath(path_to_source)[end-1:end]...)

function source_path(pkg::PackageSpec,path_to_external)
    return is_stdlib(pkg.uuid)    ? Types.stdlib_path(pkg.name) :
        pkg.repo.url  !== nothing ? join_external_source(path_to_external,find_installed(pkg.name, pkg.uuid, pkg.tree_hash)) :
        pkg.tree_hash !== nothing ? join_external_source(path_to_external,find_installed(pkg.name, pkg.uuid, pkg.tree_hash)) :
        nothing
end

function download_source(ctx::Context, pkgs::Vector{PackageSpec},path; readonly=true)
    pkgs = filter(tracking_registered_version, pkgs)
    urls = load_urls(ctx, pkgs)
    return download_source(ctx, pkgs, urls, path; readonly=readonly)
end

function download_source(ctx::Context, pkgs::Vector{PackageSpec},
                        urls::Dict{UUID, Vector{String}},path_to_external; readonly=true)
    BinaryProvider.probe_platform_engines!()
    new_versions = UUID[]

    pkgs_to_install = Tuple{PackageSpec, String}[]
    for pkg in pkgs
        path = source_path(pkg,path_to_external)
        ispath(path) && continue
        push!(pkgs_to_install, (pkg, path))
        push!(new_versions, pkg.uuid)
    end

    widths = [textwidth(pkg.name) for (pkg, _) in pkgs_to_install]
    max_name = length(widths) == 0 ? 0 : maximum(widths)

    ########################################
    # Install from archives asynchronously #
    ########################################
    jobs = Channel(ctx.num_concurrent_downloads);
    results = Channel(ctx.num_concurrent_downloads);
    @async begin
        for pkg in pkgs_to_install
            put!(jobs, pkg)
        end
    end

    for i in 1:ctx.num_concurrent_downloads
        @async begin
            for (pkg, path) in jobs
                if ctx.preview
                    put!(results, (pkg, true, path))
                    continue
                end
                if ctx.use_libgit2_for_all_downloads
                    put!(results, (pkg, false, path))
                    continue
                end
                try
                    success = install_archive(urls[pkg.uuid], pkg.tree_hash, path)
                    if success && readonly
                        set_readonly(path) # In add mode, files should be read-only
                    end
                    if ctx.use_only_tarballs_for_downloads && !success
                        pkgerror("failed to get tarball from $(urls[pkg.uuid])")
                    end
                    put!(results, (pkg, success, path))
                catch err
                    put!(results, (pkg, err, catch_backtrace()))
                end
            end
        end
    end

    missed_packages = Tuple{PackageSpec, String}[]
    for i in 1:length(pkgs_to_install)
        pkg, exc_or_success, bt_or_path = take!(results)
        exc_or_success isa Exception && pkgerror("Error when installing package $(pkg.name):\n",
                                                 sprint(Base.showerror, exc_or_success, bt_or_path))
        success, path = exc_or_success, bt_or_path
        if success
            vstr = pkg.version != nothing ? "v$(pkg.version)" : "[$h]"
            printpkgstyle(ctx, :Installed, string(rpad(pkg.name * " ", max_name + 2, "─"), " ", vstr))
        else
            push!(missed_packages, (pkg, path))
        end
    end

    ##################################################
    # Use LibGit2 to download any remaining packages #
    ##################################################
    for (pkg, path) in missed_packages
        uuid = pkg.uuid
        if !ctx.preview
            install_git(ctx, pkg.uuid, pkg.name, pkg.tree_hash, urls[uuid], pkg.version::VersionNumber, path)
            readonly && set_readonly(path)
        end
        vstr = pkg.version != nothing ? "v$(pkg.version)" : "[$h]"
        printpkgstyle(ctx, :Installed, string(rpad(pkg.name * " ", max_name + 2, "─"), " ", vstr))
    end

    return new_versions
end


function main(path_to_project,path_to_external)
    !isdir(path_to_external) ? mkdir(path_to_external) : nothing
    activate(path_to_project)
    ctx=Context()

    println("Project Path : " * path_to_project)
    println("Using : " * ctx.env.manifest_file * "\n"
           *"        " * ctx.env.project_file)
    println("Copying these files to " * path_to_external)
    Base.cp(ctx.env.project_file,joinpath(path_to_external,basename(ctx.env.project_file)),force=true)
    Base.cp(ctx.env.manifest_file,joinpath(path_to_external,basename(ctx.env.manifest_file)),force=true)

    project = ctx.env.project

    registry_path = joinpath(depots1(),"registries")
    registry_path_extern = joinpath(path_to_external,"registries")

    mkpath(registry_path_extern)
    Base.cp(registry_path,registry_path_extern,force=true)

    pkgs = [ PackageSpec(k,v) for (k,v) in project.deps ]

    project_deps_resolve!(ctx.env,pkgs)
    registry_resolve!(ctx.env,pkgs)
    stdlib_resolve!(ctx,pkgs)
    ensure_resolved(ctx.env,pkgs)

    for (i, pkg) in pairs(pkgs)
        entry = manifest_info(ctx.env, pkg.uuid)
        pkgs[i] = update_package_add(pkg, entry, is_dep(ctx.env, pkg))
    end

    foreach(pkg -> ctx.env.project.deps[pkg.name] = pkg.uuid, pkgs) # update set of deps

    load_direct_deps!(ctx, pkgs)
    check_registered(ctx, pkgs)
    resolve_versions!(ctx, pkgs)
    update_manifest!(ctx, pkgs)

    new_apply = download_source(ctx, pkgs,path_to_external;readonly=false)
    write_env(ctx) # write env before building
end

path_to_project = abspath(ARGS[1])
ispath(path_to_project) || error("First argument must be the existent path of your project")
path_to_external = abspath(ARGS[2])
ispath(path_to_external) || mkpath(path_to_external)
path_to_external == path_to_project && error("Both paths cannot be equal")
main(path_to_project,path_to_external)
