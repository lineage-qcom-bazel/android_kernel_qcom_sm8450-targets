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
load("//lineage/tools:merge_dtbs.bzl", "target_merged_dtb")

def _product_condition(product):
    # config_setting defined by define_moto_product_flag() in
    # //vendor/qcom/kernel:moto_products.bzl
    return "//vendor/qcom/kernel:mmi_product_{}".format(product)

def target_kernel_dtbs(tv, kernel_path, dtbo_page_size = 4096, products = {}):
    """Merged dtb.img and dtbo.img, with per product wildcards."""
    target_merged_dtb(
        tv,
        "{}:{}".format(kernel_path, tv),
        page_size = dtbo_page_size,
        wildcards_by_condition = {
            _product_condition(product): (
                p.get("dtb_wildcard", "*"),
                p.get("dtbo_wildcard", "*"),
            )
            for product, p in products.items()
        },
    )

def target_kernel_modules(tv, kernel_path, module_path, modules, products = {}):
    """External modules (plus per product ones), their install and ABI targets."""
    product_modules = {"//conditions:default": []}
    for product, p in products.items():
        product_modules[_product_condition(product)] = [m.replace("%p", module_path).replace("%b", tv) for m in p.get("modules", [])]

    kernel_module_group(
        name = "{}_external_modules".format(tv),
        srcs = [m.replace("%p", module_path).replace("%b", tv) for m in modules] + select(product_modules),
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

def target_kernel_uapi_headers(tv, kernel_path, module_path):
    """Kernel and DDK module uapi headers merged into kernel-uapi-headers.tar.gz."""

    kernel_build = "{}:{}".format(kernel_path, tv)

    # Keep individual ddk_uapi_headers if other targets still need them
    ddk_uapi_headers(
        name = "{}_ddk_uapi_headers".format(tv),
        srcs = [
            "{}/qcom/opensource/audio-kernel:audio_uapi_headers".format(module_path),
            "{}/qcom/opensource/dataipa:dataipa_uapi_headers".format(module_path),
            "{}/qcom/opensource/display-drivers:uapi_headers".format(module_path),
            "{}/qcom/opensource/securemsm-kernel:securemsm_uapi_headers".format(module_path),
        ],
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

def target_kernel_dist(tv, kernel_path):
    """<tv>_dist: everything kernel.mk takes from the kernel platform build."""
    pkg_files(
        name = "{}_dist_files".format(tv),
        srcs = [
            "{}:{}".format(kernel_path, tv),
            ":{}_modules_install".format(tv),
            ":{}_merged_kernel_uapi_headers".format(tv),
            ":{}_merged_dtb".format(tv),
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
    msm_target,
    variant,
    modules,
    kernel_path = "//vendor/qcom/kernel",
    module_path = "//vendor/qcom/sm8450-modules",
    dtbo_page_size = 4096,
    products = {},
):
    """Kernel dist package for <msm_target>_<variant>.

    Args:
      msm_target: e.g. "parrot".
      variant: e.g. "perf".
      modules: external module labels, "%b" is replaced with <msm_target>_<variant>.
      products: dict of Motorola product (--//vendor/qcom/kernel:mmi_product)
        -> dict with optional keys:
          dtb_wildcard: like TARGET_MERGE_DTBS_WILDCARD, default "*".
          dtbo_wildcard: like TARGET_MERGE_DTBOS_WILDCARD, default "*".
          modules: extra external module labels ("%b" replaced as above).
      dtbo_page_size: page size for dtbo.img.
    """
    tv = "{}_{}".format(msm_target, variant)

    target_kernel_dtbs(tv, kernel_path, dtbo_page_size, products)
    target_kernel_modules(tv, kernel_path, module_path, modules, products)
    target_kernel_uapi_headers(tv, kernel_path, module_path)
    target_kernel_dist(tv, kernel_path)
