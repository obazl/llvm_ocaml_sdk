
# llvm_targets extension
# for each TARGET, uses rctx.template to generate

# @llvm_config//backends/llvm_TARGET.[ml,mli]
# e.g. llvm_ARM64.[ml,mli]

# Cmake also generates
# llvm/backends/TARGET_ocaml.c
# but this is unecessary since all such files are identical
# Instead, we just copy backend_ocaml.c once
# to @llvm_config/backends/backend_ocaml.c
# and it will be recompiled whenver -DTARGET=${TARGET}
# changes.

# we ignore the llvm/backends/META

# from llvm-project/docs/GettingStarted.rst:

# | LLVM_TARGETS_TO_BUILD   | A semicolon delimited list controlling which       |
# |                         | targets will be built and linked into llvm.        |
# |                         | The default list is defined as                     |
# |                         | ``LLVM_ALL_TARGETS``, and can be set to include    |
# |                         | out-of-tree targets. The default value includes:   |
# |                         | ``AArch64, AMDGPU, ARM, AVR, BPF, Hexagon, Lanai,  |
# |                         | Mips, MSP430, NVPTX, PowerPC, RISCV, Sparc,        |
# |                         | SystemZ, WebAssembly, X86, XCore``. Setting this   |
# |                         | to ``"host"`` will only compile the host           |
# |                         | architecture (e.g. equivalent to specifying ``X86``|
# |                         | on an x86 host machine) can                        |
# |                         | significantly speed up compile and test times.     |

################################################################

archmap = {
    "aarch64": "AArch64",
    "amdgpu": "AMDGPU",
    "arm": "ARM",
    "avr": "AVR",
    "bpf": "BPF",
    "hexagon": "Hexagon",
    "lanai": "Lanai",
    "mips": "Mips",
    "msp430": "MSP430",
    "nvptx": "NVPTX",
    "powerpc": "PowerPC",
    "riscv": "RISCV",
    "sparc": "Sparc",
    "systemz": "SystemZ",
    "webassembly": "WebAssembly",
    "x86": "X86",
    "xcore": "XCore"
}

#### repo rule ####
def _llvm_config_impl(rctx):
    print("LLVM_CONFIG REPO RULE")

    rctx.file(
        "MODULE.bazel",
        content = """
module(
    name = "{repo_name}",
    version = "1.0.0",
    compatibility_level = 1,
)
""".format(repo_name = rctx.name)
    )

    xarch = rctx.os.arch.lower()
    arch = archmap[xarch]
    print("ARCH: %s" % arch)

    rctx.file(
        "makevars/RULES.bzl",
        content = """
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _makevars_impl(ctx):
    t = ctx.attr._target[BuildSettingInfo].value
    if t == "host":
        arch = "{host_arch}"
    else:
        arch = t
    items = {{"LLVM_TARGET_ARCH": arch}}

    return [platform_common.TemplateVariableInfo(items)]
makevars = rule(
    implementation = _makevars_impl,
    attrs = {{ "_target": attr.label(
        default = "//target"
        ) }}
)
""".format(host_arch = arch)
    )

    rctx.file(
        "makevars/BUILD.bazel",
        content = """
load(":RULES.bzl", "makevars")
makevars(name = "makevars",
         visibility = ["//visibility:public"])
"""
    )

    rctx.file(
        "host/BUILD.bazel",
        content = """
package(default_visibility = ["//visibility:public"])
config_setting(name = "aarch64",
               flag_values = {"//llvm/target": "host"},
               constraint_values = ["@platforms//cpu:aarch64"])
config_setting(name = "x86",
               flag_values = {"//llvm/target": "host"},
               constraint_values = ["@platforms//cpu:x86_64"])
"""
        )
    rctx.file(
        "target/BUILD.bazel",
        content = """
load("@bazel_skylib//rules:common_settings.bzl", "string_flag")
string_flag(
    name = "target", build_setting_default = "host",
    visibility = ["//visibility:public"],
    values = [
        "AArch64", "AMDGPU", "ARM", "AVR", "BPF",
        "Hexagon", "Lanai", "Mips", "MSP430",
        "NVPTX", "PowerPC", "RISCV", "Sparc",
        "SystemZ", "WebAssembly", "X86", "XCore",
        "host"
    ]
)
config_setting(name = "host",
               flag_values = {":target": "host"})

config_setting(name = "aarch64",
               flag_values = {":target": "aarch64"})

config_setting(name = "x86",
               flag_values = {":target": "x86"})
"""
    )

    supported = [
        "AArch64", "AMDGPU", "ARM", "AVR", "BPF",
        "Hexagon", "Lanai", "Mips", "MSP430", "NVPTX",
        "PowerPC", "RISCV", "Sparc", "SystemZ",
        "WebAssembly", "X86", "XCore",
    ]

    content = """
load(\"@rules_ocaml//build:rules.bzl\", \"ocaml_module\")

"""
    selectors = ""
    for target in supported:
        selector = """
        "//target:{}": "llvm_{}.ml",
        "//host:{}": "llvm_{}.ml",
        """.format(target, target, target, target)
        selectors = selectors + selector

    m = "\n".join([
         "ocaml_module(",
         "    name   = \"Backend\",",
         "    struct = select({",
         selectors,
         "    }),",
         "    deps   = [",
         "        # \"//llvm/llvm:Llvm\"",
         "        \"@ocaml-llvm//llvm/backends:backend_c\"",
         "    ]",
         ")\n"
    ])

    # content = content + m

    for target in supported:
        module = "\n".join([
            "ocaml_module(",
            "    name   = \"{T}\",",
            "    struct = \"llvm_{T}.ml\",",
            "    deps   = [",
            "        # \"//llvm/llvm:Llvm\"",
            "        \"@ocaml-llvm//llvm/backends:backend_c\"",
            "    ]",
            ")\n"
        ]).format(T=target)
        content = content + module

    rctx.file(
        "backends/BUILD.bazel",
        content = content
    )

        # rctx.template(
        #     "backends/llvm_{}.ml".format(target), # output
        #     Label("@ocaml-llvm//llvm/backends:BUILD.template"),
        #     substitutions = {"@TARGET@": target},
        #     executable = False,
        # )

    if "ALL" in rctx.attr.targets:
        print("EMITTING ALL TARGETS")
        for target in supported:
            rctx.template(
                "backends/llvm_{}.ml".format(target), # output
                Label("@ocaml-llvm//llvm/backends:llvm_backend.ml.in"),
                substitutions = {"@TARGET@": target},
                executable = False,
            )

    elif "host" in  rctx.attr.targets:
        print("EMITTING HOST TARGET")
    else:
        print("EMITTING TARGETS")
        for target in rctx.attr.targets:
            if target not in supported:
                if target not in ["ALL", "host"]:
                    supported.extend(["ALL", "host"])
                    print("Supported targets: %s" % supported)
                    fail("Bad target: %s" % target)
            rctx.template(
                "backends/llvm_{}.ml".format(target), # output
                Label("@ocaml-llvm//llvm/backends:llvm_backend.ml.in"),
                substitutions = {"@TARGET@": target},
                executable = False,
            )
## end _llvm_config_impl

############
_llvm_config = repository_rule(
    implementation = _llvm_config_impl,
    attrs = {
        "_ml_template": attr.label(
            default = "//llvm/backends/llvm_backend.ml.in"
        ),
        "_mli_template": attr.label(
            default = "//llvm/backends/llvm_backend.mli.in"
        ),
        "targets": attr.string_list(
            doc = """Supported targets:
            AArch64, AMDGPU, ARM, AVR, BPF, Hexagon, Lanai, Mips,
            MSP430, NVPTX, PowerPC, RISCV, Sparc, SystemZ,
            WebAssembly, X86, XCore.
            Special targets: ALL, host
            """
        ),
    },
)

##############
## TAG CLASSES
_config = tag_class(
    attrs = {
        "targets": attr.string_list(
            doc = """Supported targets:
            AArch64, AMDGPU, ARM, AVR, BPF, Hexagon, Lanai, Mips,
            MSP430, NVPTX, PowerPC, RISCV, Sparc, SystemZ,
            WebAssembly, X86, XCore.
            Special targets: ALL, host
            """
        ),
    }
)

#### EXTENSION IMPL ####
def _ocaml_llvm_impl(module_ctx):

  print("OCAML_LLVM EXTENSION")

  # collect artifacts from across the dependency graph
  targets = []
  for mod in module_ctx.modules:
      for config in mod.tags.config:
          for target in config.targets:
              print("TARGET: %s" % target)
              targets.append(target)

  _llvm_config(name = "llvm_config",
               targets = targets)


##############################
ocaml_llvm = module_extension(
  implementation = _ocaml_llvm_impl,
  tag_classes = {"config": _config},
)
