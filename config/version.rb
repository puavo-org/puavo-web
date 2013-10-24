module PuavoUsers
  VERSION = File.open("VERSION", "r"){ |f| f.read }.strip
  GIT_COMMIT = File.open("GIT_COMMIT", "r"){ |f| f.read }.strip
end
