/*
file:供给-市场.sql
指标:单市场投放成本|上架量|市场投放成本|标准上架量
业务：C1
场景：截面表|供给周报的截面数据
标签：供给|市场成本|成本|市场|单市场投放成本|上架量|市场投放成本|标准上架量
维度：channel_level1|channel_level2|投放类型toufang_type|渠道类型名称channel_type_name|日期dt
核心表：dm_ctob_clue_detail_transform_csd_inc_ymd，dw_ctob_c1_car_source_ymd，
dim_com_city_ymd，dm_ctob_tableau_total_index_stat_ymd，
dim_mkt_channel_listing_std_coef，mkt_expense_onshelf_day
作者：宋明瑞，杨悦芳
描述：用于供给周报的市场投放成本、单上架市场成本、单标准上架市场成本
*/
-- 注意：本sql包含标准上架量，已依赖国庆哥的dim_mkt_channel_listing_std_coef系数表（市场提供），本sql无需手动改系数
WITH clue_task_onshelf AS (
    SELECT *
    FROM guazi_dw_dm.dm_ctob_clue_detail_transform_csd_inc_ymd    
    WHERE dt BETWEEN '${start}' AND '${date_y_m_d}' 
    AND ctob_busi_type_code IN (0,1)
),

-- 圈车
car_source_dim AS (
    SELECT DISTINCT 
        COALESCE(t1.clue_id_self, t1.clue_id) AS clue_id,
        SUBSTR(onshelf_time, 1, 10) AS dt,
        CASE 
            WHEN car_collect_platform IN (2,3) OR consign_choose_type IN (1, 2) THEN 'C圈车' 
            ELSE 'B圈车' 
        END AS `圈车类型`,
        CASE
            WHEN first_onshelf_biz_line = 'C2C独售-虚拟' THEN '首上虚拟寄售'
            WHEN first_onshelf_biz_line = 'C2C独售-门店' THEN '首上实体寄售'
            WHEN first_onshelf_biz_line = 'C2B' THEN '首上C2B'
            WHEN first_onshelf_biz_line = '自营C' THEN '首上自营C'
            WHEN first_onshelf_biz_line = '自营B' THEN '首上自营B'
            ELSE first_onshelf_biz_line
        END AS `首上架渠道`
    FROM guazi_dw_dw.dw_ctob_c1_car_source_ymd t1
    WHERE t1.dt = '${date_y_m_d}'
      AND t1.is_c1_clue = 1 -- C1车源
      AND SUBSTR(onshelf_time, 1, 10) IS NOT NULL -- 已经上架
),

channel as 
(SELECT distinct 
	ca_s, ca_n ,
    clue_id,
	channel_level1,channel_level2,toufang_type,
	channel_type_name,
	customer_type_name,
	channel_name
	
FROM guazi_dw_dw.dw_ctob_c1_car_source_ymd -- C1线索
WHERE dt ='${date_y_m_d}' 
AND is_c1_clue = 1 -- C1车源
)
,

city AS (
    SELECT 
        city_id, city_name, short_name, domain, city_level,
        province_name, province_short_name
    FROM guazi_dw_dwd.dim_com_city_ymd
    WHERE dt = '${date_y_m_d}'
),

dau AS (
    SELECT
            dt,
            'other' AS toufang_type,
			'other' as  channel_level1,
			'other' as channel_level2,
			'other' as channel_type_name,
			'other' as  channel_name,
            SUM(gz_dau_num) AS dau,
            SUM(c1_dau_num) AS c1_dau,
            0 AS clue_num,
			0 AS evaluate_num,
			0 AS onshelf_num,
            0 AS standard_onshelf_num,
			0 AS prepay_net_num
        FROM guazi_dw_dm.dm_ctob_tableau_total_index_stat_ymd
        WHERE dt BETWEEN '${start}' AND '${date_y_m_d}'
        AND ctob_busi_type IN ('一口价')
        GROUP BY 1
)
,
-- 单独提取每个一级分类下 end_date 最大的一条记录，专门用于超期兜底匹配
coef_max AS (
    SELECT 
        first_level_category, 
        single_listing_revenue_coef, 
        end_date AS max_end_date
    FROM (
        SELECT 
            first_level_category,
            single_listing_revenue_coef,
            end_date,
            ROW_NUMBER() OVER(PARTITION BY first_level_category ORDER BY end_date DESC) as rn
        FROM guazi_dw_import.dim_mkt_channel_listing_std_coef
    ) tmp
    WHERE rn = 1
)
,all_ as
(
	SELECT 
		a.dt, a.clue_id, a.is_salvage, a.is_75_city, a.cb_sale_type, c.city_level, a.ca_s ,
		d.`圈车类型`,  
		d.`首上架渠道`, 
		COALESCE(clue_num,0) AS clue_num,
		COALESCE(evaluate_num,0) AS evaluate_num,
		COALESCE(onshelf_num,0) AS onshelf_num,
		COALESCE(a.deliver_num,0) AS deliver_num,
		COALESCE(a.refund_num,0) AS refund_num,
		b.toufang_type,
		b.channel_name,
		b.channel_level1,
		b.channel_level2,
		b.channel_type_name,
		b.customer_type_name ,
		a.ctob_busi_type_code ,
	
		case 
		when  b.channel_level2 = '主端' and b.toufang_type = '非投放' and b.customer_type_name = 'App' then '主端-非投放-APP'
		when  b.channel_level2 = '主端' and b.toufang_type = '投放' and b.customer_type_name = 'App' then '主端-投放-APP'
		when  b.channel_level2 = '主端' and b.toufang_type = '非投放' and b.customer_type_name = '小程序' then '主端-非投放-小程序'
		when  b.channel_level2 = '主端' and b.toufang_type = '投放' and b.customer_type_name = '小程序' then '主端-投放-小程序'
		when  b.channel_level2 = '非主端' and b.toufang_type = '非投放' and b.customer_type_name = 'App' then '非主端-非投放-APP'
		when  b.channel_level2 = '非主端' and b.toufang_type = '非投放' and b.customer_type_name = '小程序' then '非主端-非投放-小程序'
		when  b.channel_level2 = '非主端' and b.toufang_type = '投放' and b.customer_type_name = 'App' then '非主端-投放-APP'
		when  b.channel_level2 = '非主端' and b.toufang_type = '投放' and b.customer_type_name = '小程序' then '非主端-投放-小程序'
		when  b.channel_level1 = '非端产品' then '非端产品'
		when  b.channel_level1 = '商务拓展' then '商务拓展'
		when  b.channel_level1 = '直播' then '直播'
		when  b.channel_type_name = '网销自建' then '网销自建'
		else '其他' end as new_type
	FROM clue_task_onshelf a
	LEFT JOIN channel b ON a.clue_id = b.clue_id 
	LEFT JOIN city c ON a.city_name = c.city_name
   
	LEFT JOIN car_source_dim d ON a.clue_id = d.clue_id AND a.dt = d.dt 
) 
,end_ as (
SELECT 
	t1.channel_level1, -- 端产品、非端产品等等
	CASE 
        WHEN channel_level1 = '非端产品' then '非端产品'
		WHEN channel_level2 = '非主端' THEN '非主端'
        WHEN channel_level1 = '商务拓展' THEN '商务拓展'
        WHEN channel_level1 = '端产品' THEN '主端'
		when channel_level1 = '直播' then '直播'
        ELSE channel_level1 
    END AS channel_level2,
    t1.toufang_type, -- 投放非投放等等
    t1.dt,
	case when t1.channel_level1 = '端产品' and channel_level2 <> '非主端' and t1.channel_type_name = '信息流' then '信息流'
	when t1.channel_level1 = '端产品' and channel_level2 <> '非主端' and t1.channel_type_name = '应用商店' then '应用商店'
	when t1.channel_level1 = '端产品' and channel_level2 <> '非主端' and t1.channel_type_name <> '应用商店' and t1.channel_type_name <> '信息流' then '其他'
	else '/' end as channel_type_name, -- 细分的
 
    SUM(CASE WHEN cb_sale_type='tob' THEN t1.onshelf_num ELSE 0 END) AS onshelf_num,
    SUM(CASE WHEN cb_sale_type='tob' THEN t1.onshelf_num * COALESCE(t2_norm.single_listing_revenue_coef, t2_max.single_listing_revenue_coef) ELSE 0 END) AS standard_onshelf_num
   
FROM all_ t1 
-- 规则1：正常判断 t1.dt 是否落在 [start_date, end_date] 区间内
left join guazi_dw_import.dim_mkt_channel_listing_std_coef t2_norm 
       ON t1.new_type = t2_norm.first_level_category
      AND t1.dt >= t2_norm.start_date 
      AND t1.dt <= t2_norm.end_date
-- 规则2：如果 t1.dt 超出了该分类最大的 end_date，则匹配兜底表
LEFT JOIN coef_max t2_max 
       ON t1.new_type = t2_max.first_level_category
      AND t1.dt > t2_max.max_end_date
	 group by 1,2,3,4,5
)
select 
-- e.channel_level1
-- ,e.channel_level2
mk.channel_level1  
,mk.channel_level2
-- ,e.toufang_type
,mk.toufang_type
-- ,e.dt
,mk.channel_type_name
,mk.dt
-- ,e.channel_type_name

,sum(mkt_expense_per_onshelf)mkt_expense_per_onshelf
,sum(mk.onshelf_num)onshelf_num
-- ,sum(e.onshelf_num)onshelf_num
,sum(mkt_expense)mkt_expense
,sum(standard_onshelf_num)standard_onshelf_num

from end_ e 
left join (
select 
channel_level1
,channel_level2
,toufang_type
,channel_type_name
,SUBSTR(dt, 1, 10) AS dt
,mkt_expense_per_onshelf
,onshelf_num
,mkt_expense
from
guazi_dw_import.mkt_expense_onshelf_day ) mk 
on e.channel_level1=mk.channel_level1 
and e.channel_level2 = mk.channel_level2
and e.toufang_type = mk.toufang_type
and e.channel_type_name=mk.channel_type_name
date_format(e.dt,'%Y-%m-%d')
=
date_format(mk.dt,'%Y-%m-%d')
where e.toufang_type = '投放' 
and e.channel_level1 in ('端产品','非端产品','商务拓展','直播')
GROUP BY 1, 2, 3, 4, 5 
