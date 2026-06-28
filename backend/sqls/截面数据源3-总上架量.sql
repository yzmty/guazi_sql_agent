/*
文件: 截面数据源3-总上架量.sql
指标: 上架量
业务: C1车源上架量统计
场景: 统计C1车源每日总上架量，按价格段、燃油类型维度汇总
标签: 截面|上架量|C1|价格段|燃油类型
维度: dt|价格带model_price_region|宽价格带model_price_region_wide|燃油类型fuel_type
核心表: dim_ctob_auction_car_source_ymd
作者: 未知
描述: 从B端车源维表统计C1车源每日上架量，按上架时间、价格段、燃油类型分组汇总
*/
-- 截面数据源3:总上架量
SELECT
	SUBSTRING(onshelf_time, 1, 10) AS dt -- 上架时间
	,case
			when (seller_model_price * 1.0 / 10000) > 0   and (seller_model_price * 1.0 / 10000) <= 1   then 'a.(0-1]'
			when (seller_model_price * 1.0 / 10000) > 1   and (seller_model_price * 1.0 / 10000) <= 2   then 'b.(1-2]'
			when (seller_model_price * 1.0 / 10000) > 2   and (seller_model_price * 1.0 / 10000) <= 4   then 'c.(2-4]'
			when (seller_model_price * 1.0 / 10000) > 4   and (seller_model_price * 1.0 / 10000) <= 6.5 then 'd.(4-6.5]'
			when (seller_model_price * 1.0 / 10000) > 6.5 and (seller_model_price * 1.0 / 10000) <= 10  then 'e.(6.5-10]'
			when (seller_model_price * 1.0 / 10000) > 10  and (seller_model_price * 1.0 / 10000) <= 15  then 'f.(10-15]'
			when (seller_model_price * 1.0 / 10000) > 15  and (seller_model_price * 1.0 / 10000) <= 20  then 'g.(15-20]'
			when (seller_model_price * 1.0 / 10000) > 20  and (seller_model_price * 1.0 / 10000) <= 30  then 'h.(20-30]'
			when (seller_model_price * 1.0 / 10000) > 30  and (seller_model_price * 1.0 / 10000) <= 50  then 'i.(30-50]'
			when (seller_model_price * 1.0 / 10000) > 50                                                then 'j.(50+)'
		end model_price_region -- 价格段
	,case
		when (seller_model_price * 1.0 / 10000) > 0  and (seller_model_price * 1.0 / 10000) <= 4 then '(0-4]'
		when (seller_model_price * 1.0 / 10000) > 4 and (seller_model_price * 1.0 / 10000) <= 10 then '(4-10]'
		when (seller_model_price * 1.0 / 10000) > 10 and (seller_model_price * 1.0 / 10000) <= 15 then '(10-15]'
		when (seller_model_price * 1.0 / 10000) > 15 and (seller_model_price * 1.0 / 10000) <= 20 then '(15-20]'
		when (seller_model_price * 1.0 / 10000) > 20                                             then '(20+)'
	end model_price_region_wide -- 宽价格段
	,case when fuel_type in (12,13,20) then '新能源' else '燃油车' end as fuel_type -- 燃油类型
	,count(distinct clue_id) as `上架量` -- clue_id线索id
FROM guazi_dw_dwd.dim_ctob_auction_car_source_ymd  -- B端车源信息维表
WHERE dt = '${date_y_m_d}'
AND SUBSTRING(onshelf_time, 1, 10) BETWEEN '${start}' AND '${date_y_m_d}'
AND ctob_busi_type_code IN (0,1) -- 所有C1新上架量 拍卖业务类型：0:其他 1:C线索 2:经销商C线索 3:经销商B线索 4:开放平台 5:斩仓车 6:淘车 7:B2C同售B2B 8:B2C满7天自动同售B2B 9 B收车 10C收车
group by 1,2,3,4