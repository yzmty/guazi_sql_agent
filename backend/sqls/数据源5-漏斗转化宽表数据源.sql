/*
文件: 数据源5-漏斗转化宽表数据源.sql
指标: 上架量|当日停售车源量|3日停售车源量|7日停售车源量|14日停售车源量|21日停售车源量|30日停售车源量|60日停售车源量|当日C2C已定量|3日C2C已定量|7日C2C已定量|14日C2C已定量|21日C2C已定量|30日C2C已定量|60日C2C已定量|当日C2B已定量|3日C2B已定量|7日C2B已定量|14日C2B已定量|21日C2B已定量|30日C2B已定量|60日C2B已定量|当日C收车已定量|3日C收车已定量|7日C收车已定量|14日C收车已定量|21日C收车已定量|30日C收车已定量|60日C收车已定量|当日B收车已定量|3日B收车已定量|7日B收车已定量|14日B收车已定量|21日B收车已定量|30日B收车已定量|60日B收车已定量|当日B收车后C2B已定量|3日B收车后C2B已定量|7日B收车后C2B已定量|14日B收车后C2B已定量|21日B收车后C2B已定量|30日B收车后C2B已定量|60日B收车后C2B已定量|当日C收车后C2B已定量|3日C收车后C2B已定量|7日C收车后C2B已定量|14日C收车后C2B已定量|21日C收车后C2B已定量|30日C收车后C2B已定量|60日C收车后C2B已定量|当日C收车后C2C已定量|3日C收车后C2C已定量|7日C收车后C2C已定量|14日C收车后C2C已定量|21日C收车后C2C已定量|30日C收车后C2C已定量|60日C收车后C2C已定量|C1_t0|C1_t3|C1_t7|C1_t14|C1_t21|C1_t30|C1_t60|平台_t0|平台_t3|平台_t7|平台_t14|平台_t21|平台_t30|平台_t60
业务: C1上架漏斗转化，包括所有渠道的已定量数据，以及C1视角和平台视角的已定量数据
场景: 按上架日期和燃油类型统计C1车源的上架量、停售量、各渠道已定量（C2C/C2B/C收车/B收车），以及C1视角和平台视角的已定量，用于漏斗转化分析
标签: 上架|停售|已定量|C2C|C2B|C收车|B收车|C1视角|平台视角|漏斗|转化|燃油|新能源|燃油类型
维度: onshelf_dt（上架日期）|fuel_type（能源类型）
核心表: dm_ctob_fatsbi_c1_onshelf_transform_fd_ymd
作者: 未知
描述: 按上架日期和能源类型统计上架量、停售量、各渠道已定量及C1、平台视角已定量
*/
-- 数据源5：漏斗转化宽表数据源
SELECT
a.onshelf_dt,
a.fuel_type,
SUM(a.onshelf_num) AS `上架量`,
-- 停售相关
SUM(a.stop_sale_num_0) AS `当日停售车源量`,
SUM(a.stop_sale_num_3) AS `3日停售车源量`,
SUM(a.stop_sale_num_7) AS `7日停售车源量`,
SUM(a.stop_sale_num_14) AS `14日停售车源量`,
SUM(a.stop_sale_num_21) AS `21日停售车源量`,
SUM(a.stop_sale_num_30) AS `30日停售车源量`,
SUM(a.stop_sale_num_60) AS `60日停售车源量`,
-- C2C 已定量
SUM(a.c2c_prepay_num_0) AS `当日C2C已定量`,
SUM(a.c2c_prepay_num_3) AS `3日C2C已定量`,
SUM(a.c2c_prepay_num_7) AS `7日C2C已定量`,
SUM(a.c2c_prepay_num_14) AS `14日C2C已定量`,
SUM(a.c2c_prepay_num_21) AS `21日C2C已定量`,
SUM(a.c2c_prepay_num_30) AS `30日C2C已定量`,
SUM(a.c2c_prepay_num_60) AS `60日C2C已定量`,
-- C2B 已定量
SUM(a.c2b_prepay_num_0) AS `当日C2B已定量`,
SUM(a.c2b_prepay_num_3) AS `3日C2B已定量`,
SUM(a.c2b_prepay_num_7) AS `7日C2B已定量`,
SUM(a.c2b_prepay_num_14) AS `14日C2B已定量`,
SUM(a.c2b_prepay_num_21) AS `21日C2B已定量`,
SUM(a.c2b_prepay_num_30) AS `30日C2B已定量`,
SUM(a.c2b_prepay_num_60) AS `60日C2B已定量`,

-- C收车已定量
sum(a.c_acquisition_prepay_num_0) as `当日C收车已定量`,
sum(a.c_acquisition_prepay_num_3) as `3日C收车已定量`,
sum(a.c_acquisition_prepay_num_7) as `7日C收车已定量`,
sum(a.c_acquisition_prepay_num_14) as `14日C收车已定量`,
sum(a.c_acquisition_prepay_num_21) as `21日C收车已定量`,
sum(a.c_acquisition_prepay_num_30) as `30日C收车已定量`,
sum(a.c_acquisition_prepay_num_60) as `60日C收车已定量`,

-- B收车已定量
sum(a.b_acquisition_prepay_num_0) as `当日B收车已定量`,
sum(a.b_acquisition_prepay_num_3) as `3日B收车已定量`,
sum(a.b_acquisition_prepay_num_7) as `7日B收车已定量`,
sum(a.b_acquisition_prepay_num_14) as `14日B收车已定量`,
sum(a.b_acquisition_prepay_num_21) as `21日B收车已定量`,
sum(a.b_acquisition_prepay_num_30) as `30日B收车已定量`,
sum(a.b_acquisition_prepay_num_60) as `60日B收车已定量`,

-- B 收车后 C2B 已定量（补全图片字段）
SUM(a.b_acquisition_c2b_prepay_num_0) AS `当日B收车后C2B已定量`,
SUM(a.b_acquisition_c2b_prepay_num_3) AS `3日B收车后C2B已定量`,
SUM(a.b_acquisition_c2b_prepay_num_7) AS `7日B收车后C2B已定量`,
SUM(a.b_acquisition_c2b_prepay_num_14) AS `14日B收车后C2B已定量`,
SUM(a.b_acquisition_c2b_prepay_num_21) AS `21日B收车后C2B已定量`,
SUM(a.b_acquisition_c2b_prepay_num_30) AS `30日B收车后C2B已定量`,
SUM(a.b_acquisition_c2b_prepay_num_60) AS `60日B收车后C2B已定量`,

-- C 收车后 C2B 已定量（补全图片字段）
SUM(a.c_acquisition_c2b_prepay_num_0) AS `当日C收车后C2B已定量`,
SUM(a.c_acquisition_c2b_prepay_num_3) AS `3日C收车后C2B已定量`,
SUM(a.c_acquisition_c2b_prepay_num_7) AS `7日C收车后C2B已定量`,
SUM(a.c_acquisition_c2b_prepay_num_14) AS `14日C收车后C2B已定量`,
SUM(a.c_acquisition_c2b_prepay_num_21) AS `21日C收车后C2B已定量`,
SUM(a.c_acquisition_c2b_prepay_num_30) AS `30日C收车后C2B已定量`,
SUM(a.c_acquisition_c2b_prepay_num_60) AS `60日C收车后C2B已定量`,

-- C 收车后 C2C 已定量（补全图片字段）
SUM(a.c_acquisition_c2c_prepay_num_0) AS `当日C收车后C2C已定量`,
SUM(a.c_acquisition_c2c_prepay_num_3) AS `3日C收车后C2C已定量`,
SUM(a.c_acquisition_c2c_prepay_num_7) AS `7日C收车后C2C已定量`,
SUM(a.c_acquisition_c2c_prepay_num_14) AS `14日C收车后C2C已定量`,
SUM(a.c_acquisition_c2c_prepay_num_21) AS `21日C收车后C2C已定量`,
SUM(a.c_acquisition_c2c_prepay_num_30) AS `30日C收车后C2C已定量`,
SUM(a.c_acquisition_c2c_prepay_num_60) AS `60日C收车后C2C已定量`,

-- C1视角
sum(a.c2c_prepay_num_0+ a.c2b_prepay_num_0+ a.c_acquisition_prepay_num_0+ a.b_acquisition_prepay_num_0) as `C1_t0`,
sum(a.c2c_prepay_num_3+ a.c2b_prepay_num_3+ a.c_acquisition_prepay_num_3+ a.b_acquisition_prepay_num_3) as `C1_t3`,
sum(a.c2c_prepay_num_7+ a.c2b_prepay_num_7+ a.c_acquisition_prepay_num_7+ a.b_acquisition_prepay_num_7) as `C1_t7`,
sum(a.c2c_prepay_num_14+ a.c2b_prepay_num_14+ a.c_acquisition_prepay_num_14+ a.b_acquisition_prepay_num_14) as `C1_t14`,
sum(a.c2c_prepay_num_21+ a.c2b_prepay_num_21+ a.c_acquisition_prepay_num_21+ a.b_acquisition_prepay_num_21) as `C1_t21`,
sum(a.c2c_prepay_num_30+ a.c2b_prepay_num_30+ a.c_acquisition_prepay_num_30+ a.b_acquisition_prepay_num_30) as `C1_t30`,
sum(a.c2c_prepay_num_60+ a.c2b_prepay_num_60+ a.c_acquisition_prepay_num_60+ a.b_acquisition_prepay_num_60) as `C1_t60` ,
  
-- 平台视角
sum(a.c2c_prepay_num_0 + a.c2b_prepay_num_0 + a.b_acquisition_c2b_prepay_num_0 + a.c_acquisition_c2b_prepay_num_0 + a.c_acquisition_c2c_prepay_num_0) as `平台_t0`,
sum(a.c2c_prepay_num_3 + a.c2b_prepay_num_3 + a.b_acquisition_c2b_prepay_num_3 + a.c_acquisition_c2b_prepay_num_3 + a.c_acquisition_c2c_prepay_num_3) as `平台_t3`,
sum(a.c2c_prepay_num_7 + a.c2b_prepay_num_7 + a.b_acquisition_c2b_prepay_num_7 + a.c_acquisition_c2b_prepay_num_7 + a.c_acquisition_c2c_prepay_num_7) as `平台_t7`,
sum(a.c2c_prepay_num_14 + a.c2b_prepay_num_14 + a.b_acquisition_c2b_prepay_num_14 + a.c_acquisition_c2b_prepay_num_14 + a.c_acquisition_c2c_prepay_num_14) as `平台_t14`,
sum(a.c2c_prepay_num_21 + a.c2b_prepay_num_21 + a.b_acquisition_c2b_prepay_num_21 + a.c_acquisition_c2b_prepay_num_21 + a.c_acquisition_c2c_prepay_num_21) as `平台_t21`,
sum(a.c2c_prepay_num_30 + a.c2b_prepay_num_30 + a.b_acquisition_c2b_prepay_num_30 + a.c_acquisition_c2b_prepay_num_30 + a.c_acquisition_c2c_prepay_num_30) as `平台_t30`,
sum(a.c2c_prepay_num_60 + a.c2b_prepay_num_60 + a.b_acquisition_c2b_prepay_num_60 + a.c_acquisition_c2b_prepay_num_60 + a.c_acquisition_c2c_prepay_num_60) as `平台_t60`

FROM guazi_dw_dm.dm_ctob_fatsbi_c1_onshelf_transform_fd_ymd a  -- C1上架漏斗转化
WHERE 
a.onshelf_dt >= '2025-11-01'  -- 上架时间
AND a.dt = '${date_y_m_d}'
GROUP BY 
a.onshelf_dt, 
a.fuel_type
ORDER BY 
a.onshelf_dt DESC, 
a.fuel_type