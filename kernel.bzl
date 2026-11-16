# SPDX-License-Identifier: GPL-2.0

load("@rules_pkg//pkg:install.bzl", "pkg_install")
load("@rules_pkg//pkg:mappings.bzl", "pkg_files", "strip_prefix")
load(
    "//build/kernel/kleaf:kernel.bzl",
    "ddk_uapi_headers",
    "kernel_abi",
    "kernel_module_group",
    "kernel_modules_install",
    "merged_kernel_uapi_headers",
)
load("//build/kernel/kleaf:hermetic_tools.bzl", "hermetic_genrule")
load("//system/tools/dtbtool:merge_dtbs.bzl", "target_merged_dtb")

def target_kernel_modules(tv, kernel_path, module_path, modules):

    """External modules, their install and ABI targets."""
    kernel_module_group(
        name = "{}_external_modules".format(tv),
        srcs = [m.replace("%p", module_path).replace("%b", tv) for m in modules],
    )

    kernel_modules_install(
        name = "{}_modules_install".format(tv),
        kernel_build = "{}:{}".format(kernel_path, tv),
        kernel_modules = [
            ":{}_external_modules".format(tv),
        ],
    )

    kernel_abi(
        name = "{}_abi".format(tv),
        kernel_build = "{}:{}".format(kernel_path, tv),
        kernel_modules = [
            ":{}_external_modules".format(tv),
        ],
        module_grouping = False,
    )

def target_kernel_uapi_headers(tv, kernel_path, module_path, headers):
    """Kernel and DDK module uapi headers merged into kernel-uapi-headers.tar.gz."""

    kernel_build = "{}:{}".format(kernel_path, tv)

    # Keep individual ddk_uapi_headers if other targets still need them
    ddk_uapi_headers(
        name = "{}_ddk_uapi_headers".format(tv),
        srcs = [h.replace("%p", module_path) for h in headers],
        out = "{}/ddk-uapi-headers.tar.gz".format(tv),
        kernel_build = kernel_build,
    )

    hermetic_genrule(
        name = "{}_merged_kernel_uapi_headers".format(tv),
        srcs = [
            "{}_uapi_headers".format(kernel_build),
            ":{}_ddk_uapi_headers".format(tv),
        ],
        outs = [
            "{}/kernel-uapi-headers.tar.gz".format(tv),
        ],
        cmd = """
            mkdir -p out
            tar -xzf $$(find bazel-out/ -name kernel-uapi-headers.tar.gz -print -quit) -C out
            tar -xzf $$(find bazel-out/ -name ddk-uapi-headers.tar.gz -print -quit) -C out
            tar -czf $(@D)/kernel-uapi-headers.tar.gz -C out .
        """,
    )

    pkg_files(
        name = "{}_uapi_headers_dist_files".format(tv),
        srcs = [
            ":{}_merged_kernel_uapi_headers".format(tv),
        ],
        strip_prefix = strip_prefix.files_only(),
    )

    pkg_install(
        name = "{}_uapi_headers_dist".format(tv),
        srcs = [":{}_uapi_headers_dist_files".format(tv)],
        destdir = "out/{}/dist".format(tv),
    )

def target_kernel_dist(tv, kernel_path, packages):
    """<tv>_dist: everything kernel.mk takes from the kernel platform build."""
    pkg_files(
        name = "{}_dist_files".format(tv),
        srcs = packages + [
            # Mixed build: Additional GKI artifacts.
            "//vendor/qcom/kernel:kernel_aarch64",
            "//vendor/qcom/kernel:kernel_aarch64_modules",
            "//vendor/qcom/kernel:kernel_aarch64_images_system_dlkm_image",
        ],
        strip_prefix = strip_prefix.files_only(),
    )

    pkg_install(
        name = "{}_dist".format(tv),
        srcs = [":{}_dist_files".format(tv)],
        destdir = "out/{}/dist".format(tv),
    )

def target_kernel_package(
    target,
    variant,
    kernel_path,
    module_path,
    headers = [],
    modules = [],
    dtbo_image = False,
    dtbo_page_size = 4096,
):
    """Kernel dist package for <target>_<variant>.

    Args:
      target: e.g. "parrot".
      variant: e.g. "perf".
      modules: external module labels, "%b" is replaced with <target>_<variant>.
      dtbo_page_size: page size for dtbo.img.
    """
    tv = "{}_{}".format(target, variant)

    kernel_build = "{}:{}".format(kernel_path, tv)
    packages = [kernel_build]
    if modules:
        target_kernel_modules(tv, kernel_path, module_path, modules)
        packages.append(":{}_modules_install".format(tv))
    if headers:
        target_kernel_uapi_headers(tv, kernel_path, module_path, headers)
        packages.append(":{}_merged_kernel_uapi_headers".format(tv))
    if dtbo_image:
        target_merged_dtb(tv, kernel_build, page_size = dtbo_page_size)
        packages.append(":{}_merged_dtb".format(tv))
    target_kernel_dist(tv, kernel_path, packages)
