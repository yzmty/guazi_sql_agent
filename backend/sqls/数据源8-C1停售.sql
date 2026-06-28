/*
文件: 数据源8-C1停售.sql
指标: 上架量|T0_停售量|T3_停售量|T7_停售量|T14_停售量|T21_停售量|T30_停售量|T60_停售量
业务: 首上架车源停售率分析
场景: 按上架日期、能源类型、价格带统计C1车源的上架量及不同时间窗口（T0/T3/T7/T14/T21/T30/T60）的停售量，用于分析车源停售率和停售周期
标签: 首上架|停售|价格带|燃油|新能源|C1|停售率|转化
维度: onshelf_dt（上架日期）|fuel_type（能源类型）|price_region（价格带）
核心表: dm_ctob_fatsbi_c1_onshelf_transform_fd_detail_ymd
作者: 宋明瑞|杨悦芳
描述: 按上架日期、能源类型、价格带统计上架量及T0~T60天停售量
*/
select 
	onshelf_dt
	,fuel_type
	,case when model_price_region in ('a.(0-1]','b.(1-2]','c.(2-4]') then '(0-4]'
	when model_price_region in ('d.(4-6.5]','e.(6.5-10]') then '(4-10]'
	when model_price_region in ('h.(20-30]','i.(30-50]','j.(50+)') then '(20+）'
	when model_price_region in ('f.(10-15]') then '(10-15]'
	when model_price_region in ('g.(15-20]') then '(15-20]'
	end as price_region
	,sum(onshelf_num) '上架量'
	,sum(stop_sale_num_0) as  'T0_停售量'
	,sum(case when datediff(cast('${date_y_m_d}' as date),cast(onshelf_dt as date)) >=3 then stop_sale_num_3 else null end) as  'T3_停售量'
	,sum(case when datediff(cast('${date_y_m_d}' as date),cast(onshelf_dt as date)) >=7 then stop_sale_num_7 else null end) as  'T7_停售量'
	,sum(case when datediff(cast('${date_y_m_d}' as date),cast(onshelf_dt as date)) >=14 then stop_sale_num_14 else null end) as  'T14_停售量'
	,sum(case when datediff(cast('${date_y_m_d}' as date),cast(onshelf_dt as date)) >=21 then stop_sale_num_21 else null end) as  'T21_停售量'
	,sum(case when datediff(cast('${date_y_m_d}' as date),cast(onshelf_dt as date)) >=30 then stop_sale_num_30 else null end) as  'T30_停售量'
	,sum(case when datediff(cast('${date_y_m_d}' as date),cast(onshelf_dt as date)) >=60 then stop_sale_num_60 else null end) as  'T60_停售量'

from guazi_dw_dm.dm_ctob_fatsbi_c1_onshelf_transform_fd_detail_ymd
where dt = '${date_y_m_d}'
and onshelf_dt between '${start}' and '${date_y_m_d}'
group by 1,2,3