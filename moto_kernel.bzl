# SPDX-License-Identifier: GPL-2.0

load(
    "//build/kernel/kleaf:kernel.bzl",
    "kernel_module_group",
)
load("//system/tools/dtbtool:merge_dtbs.bzl", "target_merged_dtb")
load(
    ":kernel.bzl",
    "target_kernel_dist",
    "target_kernel_modules",
    "target_kernel_uapi_headers"
)

# config_setting defined by define_moto_product_flag() in
# //vendor/qcom/kernel:moto_products.bzl
def _product_condition(product):
    return "//vendor/qcom/kernel:mmi_product_{}".format(product)

def moto_kernel_package(
    msm_target,
    variant,
    headers = [],
    modules = [],
    kernel_path = "//vendor/qcom/kernel",
    module_path = "//vendor/qcom/sm8450-modules",
    dtbo_image = True,
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
          modules: extra external module labels ("%b" replaced as above).
      dtbo_page_size: page size for dtbo.img.
    """
    tv = "{}_{}".format(msm_target, variant)
    kernel_build = "{}:{}".format(kernel_path, tv)

    packages = [kernel_build]
    if modules:
        kernel_modules = list(modules)

        # Per-product extra modules live in their own group so the select()
        # never reaches target_kernel_modules (which iterates over a list).
        if products:
            product_modules = {"//conditions:default": []}
            for product, p in products.items():
                product_modules[_product_condition(product)] = [
                    m.replace("%p", module_path).replace("%b", tv)
                    for m in p.get("modules", [])
                ]
            kernel_module_group(
                name = "{}_product_modules".format(tv),
                srcs = select(product_modules),
            )
            kernel_modules.append(":{}_product_modules".format(tv))
        target_kernel_modules(tv, kernel_path, module_path, kernel_modules)
        packages.append(":{}_modules_install".format(tv))
    if headers:
        target_kernel_uapi_headers(tv, kernel_path, module_path, headers)
        packages.append(":{}_merged_kernel_uapi_headers".format(tv))
    if dtbo_image:
        target_merged_dtb(
            tv,
            kernel_build,
            page_size = dtbo_page_size,
            dtb_wildcard = "*",
            dtbo_wildcard = "*",
        )
        packages.append(":{}_merged_dtb".format(tv))
    target_kernel_dist(tv, kernel_path, packages)
