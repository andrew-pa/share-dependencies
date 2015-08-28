require 'git'

#Git.configure do |config|
#    config.binary_path = ARGV[1]
#end

def scrub_path(p)
    np = ""
    for i in 0..(p.size-1)
        c = p[i]
        if c == '/'
            c = '\\'
        end
        np += c
    end
    np
end

include_dir = scrub_path(ARGV[0] + '/include')
libd_dir = scrub_path(ARGV[0] + '/lib/Debug')
libr_dir = scrub_path(ARGV[0] + '/lib/Release')

begin
    Dir.mkdir(include_dir)
rescue
end
begin
    Dir.mkdir(libd_dir)
rescue
end
begin
    Dir.mkdir(libr_dir)
rescue
end


require 'zip'

def unzip_file (file, destination)
    Zip::ZipFile.open(file) do |zip_file|
        zip_file.each do |f|
            f_path = File.join(destination, f.name)
            FileUtils.mkdir_p(File.dirname(f_path))
            f.extract(f_path)
        end
    end
end

def robocopy(from_path, to_path)
    #if Windows
    system("robocopy", "/E", scrub_path(from_path), scrub_path(to_path))
end

def copy(from_path, to_path)
    #if Windows
    puts("copy", scrub_path(from_path), scrub_path(to_path))
    system("copy", scrub_path(from_path), scrub_path(to_path))
end

def cmake(path, options)
    begin
        Dir.mkdir("#{path}/build")
    rescue
    end
    puts("cmake #{options} #{path}")
    Process.wait spawn("cmake #{options} ..", :chdir=>"#{path}/build")
end



def run_builder(path)
    #if Windows
    winpath = scrub_path(path)
    system("msbuild.bat", "/p:Configuration=Debug", winpath)
    system("msbuild.bat", "/p:Configuration=Release", winpath)
end

def run_builder_cmake(path)
    #cmake(path+'/build', "--build .")
    Process.wait spawn("cmake --build .", :chdir=>"#{path}/build")
    #cmake(path+'/build', "--build . --config Release")
    Process.wait spawn("cmake --build . --config Release", :chdir=>"#{path}/build")
end


def open_or_clone(spath, rpath)
    force_force_build = ARGV.size > 1 && ARGV[1] == '-fb'
    ppath = "#{ARGV[0]}/src/#{spath}"
    if File.exist?(ppath + '/.git')
        return Git.open(ppath), false || force_force_build
    else
        return Git.clone(rpath, spath, :path=>"#{ARGV[0]}/src/"), true || force_force_build
    end
end

def update_repo(repo)
    old_status = repo.show
    repo.pull
    new_status = repo.show
    if old_status != new_status
        return [old_status, new_status]
    else
        return nil
    end
end


#update GLM
glm_path = ARGV[0] + '/src/glm'
glm_repo, force_build = open_or_clone('glm', 'https://github.com/g-truc/glm')
#begin
#    glm_repo = Git.open(glm_path)
#rescue
#    force_build = true
#    glm_repo = Git.clone('https://github.com/g-truc/glm', 'glm', :path=>ARGV[0]+'/src')
#end
glm_status = update_repo(glm_repo)
if glm_status || force_build
    puts "GLM update [#{glm_status[0]} => #{glm_status[1]}]" if !force_build
    #Copy GLM to include
    robocopy(glm_path + '/glm', include_dir + '/glm')
else
    puts "GLM up to date"
end

#update assimp
assimp_path = ARGV[0] + '/src/assimp'
assimp_repo, force_build = open_or_clone('assimp', 'https://github.com/assimp/assimp')
assimp_status = update_repo(assimp_repo)
if assimp_status || force_build
    if force_build
        puts "Assimp new/forced"
    else
        puts "Assimp update [#{assimp_status[0]} => #{assimp_status[1]}]"
    end
    #build assimp

    cmake(assimp_path, "-DASSIMP_BUILD_ASSIMP_TOOLS:BOOL=OFF")

    run_builder_cmake(assimp_path)

    #copy files
    robocopy(assimp_path + '/include', include_dir)
    copy(assimp_path + '/build/code/Debug/assimp-*-mtd.dll', libd_dir)
    copy(assimp_path + '/build/code/Release/assimp-*-mt.dll', libr_dir)

    copy(assimp_path + '/build/code/Debug/assimp-*-mtd.lib', libd_dir)
    copy(assimp_path + '/build/code/Release/assimp-*-mt.lib', libr_dir)

    copy(assimp_path + '/build/code/Debug/assimp-*-mtd.pdb', libd_dir)
else
    puts "Assimp up to date"
end

#update freetype
freetype_path = scrub_path(ARGV[0] + '/src/freetype')
freetype_repo, force_build = open_or_clone('freetype', 'http://git.sv.nongnu.org/r/freetype/freetype2.git')
freetype_status = update_repo(freetype_repo)
if freetype_status || force_build
    if force_build
        puts "Freetype new/forced"
    else
        puts "Freetype update [#{freetype_status[0]} => #{freetype_status[1]}]"
    end

    #if Windows upgrade VS2010 -> newest VS project files
    system("#{ENV['ProgramFiles(x86)']}\\Microsoft Visual Studio 14.0\\Common7\\IDE\\devenv.exe",
        freetype_path+"\\builds\\windows\\vc2010\\freetype.sln", "/Upgrade")
    #build freetype
    run_builder(freetype_path+"\\builds\\windows\\vc2010\\freetype.sln")

    #copy files
    robocopy(freetype_path + '/include', include_dir)
    copy(freetype_path + '/objs/vc2010/Win32/freetype26.lib', libr_dir+'/freetype.lib')
    copy(freetype_path + '/objs/vc2010/Win32/freetype26d.lib', libd_dir+'/freetype.lib')
    copy(freetype_path + '/objs/vc2010/Win32/freetype26d.pdb', libd_dir+'/freetype.pdb')
else
    puts "Freetype up to date"
end

def git_dep(disk_path, remote_path, git_dir, name, real_force_build)
    path = scrub_path(disk_path+git_dir)
    repo, force_build = open_or_clone(git_dir, remote_path)
    status = update_repo(repo)
    force_build = force_build || real_force_build
    if status || force_build
        if force_build
            puts "#{name} new/forced"
        else
            puts "#{name} update [#{status[0]} => #{status[1]}]"
        end

        yield path, repo
    else
        puts "#{name} up to date"
    end
end

#update GLEW
glew_path = scrub_path(ARGV[0] + '/src/glew')
glew_version = '1.12.0'
existing_glew_src = File.exist?(glew_path)
begin
    Dir.mkdir(glew_path)
    unzip_file(scrub_path(ARGV[0]+'/pack/glew.zip'), glew_path)
rescue
    existing_glew_src = true
end

if !existing_glew_src || (File.atime(glew_path) < File.atime(ARGV[0]+'/pack/glew.zip'))
    #build GLEW
    puts("Building GLEW #{File.atime(glew_path)} < #{File.atime(ARGV[0]+'/pack/glew.zip')}")
    glew_src_path = glew_path + "/glew-#{glew_version}"
    run_builder(glew_src_path + '/build/vc12/glew.sln')
    robocopy(glew_src_path + '/include', include_dir)
    copy(glew_src_path + '/bin/Debug/Win32/glew32d.dll', libd_dir + '/glew32d.dll')
    copy(glew_src_path + '/bin/Debug/Win32/glew32d.pdb', libd_dir + '/glew32d.pdb')
    copy(glew_src_path + '/bin/Release/Win32/glew32.dll', libr_dir + '/glew32.dll')
    copy(glew_src_path + '/lib/Debug/Win32/glew32d.lib', libd_dir + '/glew32.lib')
    copy(glew_src_path + '/lib/Release/Win32/glew32.lib', libr_dir + '/glew32.lib')
else
    puts("GLEW up to date")
end

#update GLFW
git_dep("#{ARGV[0]}/src/", 'https://github.com/glfw/glfw', 'glfw', 'GLFW', false) {|path, repo|
    puts(path)
    cmake(path, "-DBUILD_SHARED_LIBS:BOOL=ON -DGLFW_BUILD_EXAMPLES:BOOL=OFF -DGLFW_BUILD_TESTS:BOOL=OFF")
    run_builder_cmake(path)
    robocopy(path+'/include', include_dir)
    copy(path+'/build/src/Debug/glfw3dll.lib', libd_dir+'/glfw3dll.lib')
    copy(path+'/build/src/Debug/glfw3dll.pdb', libd_dir+'/glfw3dll.pdb')
    copy(path+'/build/src/Debug/glfw3.dll', libd_dir+'/glfw3.dll')

    copy(path+'/build/src/Release/glfw3dll.lib', libr_dir+'/glfw3dll.lib')
    copy(path+'/build/src/Release/glfw3.dll', libr_dir+'/glfw3.dll')
}

#build SOIL
soil_path = scrub_path(ARGV[0] + '/src/soil')
existing_soil_src = File.exist?(soil_path)
begin
    Dir.mkdir(soil_path)
    unzip_file(scrub_path(ARGV[0]+'/pack/soil.zip'), soil_path)
rescue
    existing_soil_src = true
end
if !existing_soil_src || (File.atime(soil_path) < File.atime(ARGV[0]+'/pack/soil.zip'))
    #build SOIL
    soil_src_path = "#{soil_path}/Simple OpenGL Image Library"
    puts("Building SOIL #{File.atime(soil_path)} < #{File.atime(ARGV[0]+'/pack/soil.zip')}")

    #if Windows upgrade VS2010 -> newest VS project files
    system("#{ENV['ProgramFiles(x86)']}\\Microsoft Visual Studio 14.0\\Common7\\IDE\\devenv.exe",
        scrub_path("#{soil_src_path}\\projects\\VC9\\SOIL.sln"), "/Upgrade")

    #build
    run_builder(scrub_path("#{soil_src_path}\\projects\\VC9\\SOIL.sln"))

    copy("#{soil_src_path}\\src\\SOIL.h", "#{include_dir}\\SOIL.h")
    copy("#{soil_src_path}\\projects\\VC9\\Debug\\SOIL.lib", "#{libd_dir}\\SOIL.lib")
    copy("#{soil_src_path}\\projects\\VC9\\Release\\SOIL.lib", "#{libr_dir}\\SOIL.lib")

else
    puts("SOIL up to date")
end
