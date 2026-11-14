#!/usr/bin/env python
# Builds the Falemag GDExtension into bin/. See Docs/build.md.

env = SConscript("Native/godot-cpp/SConstruct", {"api_version": "4.7"})

env.Append(CPPPATH=["Native/src/"])
# One folder per system under Native/src/ (Docs/conventions.md, section 1).
sources = Glob("Native/src/*.cpp") + Glob("Native/src/*/*.cpp")

library = env.SharedLibrary(
	"bin/libfalemag{}{}".format(env["suffix"], env["SHLIBSUFFIX"]),
	source=sources,
)

env.NoCache(library)
Default(library)
