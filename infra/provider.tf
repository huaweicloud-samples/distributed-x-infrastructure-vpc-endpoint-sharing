# 请勿将 AK/SK 写入代码；部署前设置 HW_ACCESS_KEY / HW_SECRET_KEY / HW_REGION_NAME。
#   export HW_ACCESS_KEY="<HW_ACCESS_KEY>"
#   export HW_SECRET_KEY="<HW_SECRET_KEY>"
#   export HW_REGION_NAME="<REGION>"
# 区域也可通过 -var="region=cn-north-4" 或 TF_VAR_region 覆盖。
provider "huaweicloud" {
  region = var.region
}
