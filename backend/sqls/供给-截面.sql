/*
file:供给-截面.sql,
指标:dau|c1_dau|线索量|工单量|上架量|标准上架量|净已定
业务：C1
场景：截面表|供给周报的截面数据
标签：供给|截面|dau|c1_dau|线索量|工单量|上架量|标准上架量|净已定
维度：dt|投放类型toufang_type|城市等级city_level|渠道channel_level|渠道类型名称channel_type_name|渠道名称channel_name_ctob|圈车类型|首上架渠道|市场渠道new_type
核心表：dw_ctob_c1_car_source_ymd|dim_com_city_ymd|dim_mkt_channel_listing_std_coef|dm_ctob_clue_detail_transform_csd_inc_ymd|dw_ctob_c1_tob_toc_appoint_detail_ymd|dm_ctob_tableau_total_index_stat_ymd|dim_mkt_channel_listing_std_coef
作者：宋明瑞|杨悦芳
描述：用于供给周报的线索量、工单量、上架量、标准上架量、净已定的图表
*/
-- 注意：本sql包含标准上架量，已依赖国庆哥的dim_mkt_channel_listing_std_coef系数表（市场提供），本sql无需手动改系数
-- 时长明细
with 
-- 圈车
car_source_dim AS (
    SELECT DISTINCT 
        t1.clue_id,
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
city AS (
    SELECT 
        city_id, city_name, short_name, domain, city_level,
        province_name, province_short_name
    FROM guazi_dw_dwd.dim_com_city_ymd
    WHERE dt = '${date_y_m_d}'
),
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
,
-- 作为维度表（增加car_source_dim的字段）
clue_info as 
(SELECT distinct 
    t1.ca_s, t1.ca_n ,
    t1.clue_id,
    t1.channel_level1, 
    t1.channel_level2, 
    t1.toufang_type,
    t1.channel_type_name,
    t1.customer_type_name,
    t1.channel_name,
    case when t1.channel_level2 = '非主端' then '非主端-端产品'
    when t1.channel_level1 = '非端产品' then '表单'
    when t1.channel_level1 = '商务拓展' then '商务'
    when t1.channel_level1 = '端产品' then '主端'
    else t1.channel_level1 end as channel_level ,
    case 
        when t1.channel_level2 = '主端' and t1.toufang_type = '非投放' and t1.customer_type_name = 'App' then '主端-非投放-APP'
        when t1.channel_level2 = '主端' and t1.toufang_type = '投放' and t1.customer_type_name = 'App' then '主端-投放-APP'
        when t1.channel_level2 = '主端' and t1.toufang_type = '非投放' and t1.customer_type_name = '小程序' then '主端-非投放-小程序'
        when t1.channel_level2 = '主端' and t1.toufang_type = '投放' and t1.customer_type_name = '小程序' then '主端-投放-小程序'
        when t1.channel_level2 = '非主端' and t1.toufang_type = '非投放' and t1.customer_type_name = 'App' then '非主端-非投放-APP'
        when t1.channel_level2 = '非主端' and t1.toufang_type = '非投放' and t1.customer_type_name = '小程序' then '非主端-非投放-小程序'
        when t1.channel_level2 = '非主端' and t1.toufang_type = '投放' and t1.customer_type_name = 'App' then '非主端-投放-APP'
        when t1.channel_level2 = '非主端' and t1.toufang_type = '投放' and t1.customer_type_name = '小程序' then '非主端-投放-小程序'
        when t1.channel_level1 = '非端产品' then '非端产品'
        when t1.channel_level1 = '商务拓展' then '商务拓展'
        when t1.channel_level1 = '直播' then '直播'
        when t1.channel_type_name = '网销自建' then '网销自建'
    else '其他' end as new_type,
    t2.`圈车类型`,
    t2.`首上架渠道`,
    c.city_level
FROM guazi_dw_dw.dw_ctob_c1_car_source_ymd t1 -- C1线索
LEFT JOIN car_source_dim t2 ON t1.clue_id = t2.clue_id
left join city c on t1.city_name = c.city_name  -- 修正：原SQL中写的是 o.city_name，应该是 c.city_name
WHERE t1.dt = '${date_y_m_d}' 
AND t1.is_c1_clue = 1 -- C1车源
)
,
-- 线索量 工单量 上架量
clue_task_onshelf as (
select 
    dt,
    clue_id,
    cb_sale_type,
    is_salvage,
    is_75_city,
    clue_num,
    evaluate_num,
    onshelf_num
FROM guazi_dw_dm.dm_ctob_clue_detail_transform_csd_inc_ymd         
WHERE dt BETWEEN '${start}' AND '${end_date}' 
and ctob_busi_type_code = 1
),

-- 净已定
quantity_set as 
 (select 
    prepay_time
    , clue_id
    , sum(case when type='set' then 1 else 0 end) 
    - sum(case when type='set_r' then 1 else 0 end) as quantity_set
    from 
     (
         select -- 已定
            substr(prepay_time,1,10) as prepay_time
            ,clue_id
            ,'set' as type
        from guazi_dw_dw.dw_ctob_c1_tob_toc_appoint_detail_ymd
        where dt ='${date_y_m_d}'
          and ctob_busi_type_code in(1,9,10)
        and ctob_deal_busi_code not in (4,7,9) -- 剔除第一台车
        and substr(prepay_time,1,10) between '${start}' AND '${date_y_m_d}'
          group by 1,2,3

        union ALL

         select -- 已定后退
            substr(refund_time,1,10) as refund_time  
            ,clue_id
            ,'set_r' as type
        from guazi_dw_dw.dw_ctob_c1_tob_toc_appoint_detail_ymd
        where dt ='${date_y_m_d}'
          and ctob_busi_type_code in(1,9,10)
        and ctob_deal_busi_code not in (4,7,9) -- 剔除第一台车
        and substr(refund_time,1,10) between '${start}' AND '${date_y_m_d}'
          group by 1,2,3
    )t1
group by 1,2
 ) 
,
-- 这里使用这个C1线索表是为了取得自营C和自营B的平台视角售出的全部clue_id，
-- 以COALESCE(clue_id_self,clue_id) as clue_id和净已定关联，所有的clue_id都可以匹配到对应的市场渠道
clue as 
-- clueid表
(SELECT distinct 
    t1.dt,
    COALESCE(t1.clue_id_self, t1.clue_id) as clue_id,
    t1.channel_level1,t1.channel_level2,t1.toufang_type,
    t1.channel_type_name,
    t1.channel_name,
    case when t1.channel_level2 = '非主端' then '非主端-端产品'
    when t1.channel_level1 = '非端产品' then '表单'
    when t1.channel_level1 = '商务拓展' then '商务'
    when t1.channel_level1 = '端产品' then '主端'
    else t1.channel_level1 end as channel_level,
    t2.`圈车类型`,
    t2.`首上架渠道`,
    t1.city_level
FROM guazi_dw_dw.dw_ctob_c1_car_source_ymd t1 -- C1线索
LEFT JOIN car_source_dim t2 ON COALESCE(t1.clue_id_self, t1.clue_id) = t2.clue_id
WHERE t1.dt = '${date_y_m_d}'
AND t1.is_c1_clue = 1 -- C1车源
)
,
quantity_set_clue as (
select 
    q.clue_id
    ,quantity_set
    ,prepay_time
    ,c.dt
    ,c.toufang_type
    ,c.channel_level1
    ,c.channel_level2
    ,c.channel_level
    ,c.channel_type_name
    ,c.channel_name
    ,c.`圈车类型`
    ,c.`首上架渠道`
    ,c.city_level
from quantity_set q
left join clue c on c.clue_id = q.clue_id
)
-- 线索量 工单量 上架量等，和维度表关联
,
c1_channel as (
select 
    a.dt as dt,
    b.channel_level,
    b.toufang_type, 
    a.cb_sale_type,
    b.new_type,
    b.`圈车类型`,
    b.`首上架渠道`,
    b.channel_level1,
    b.channel_level2,
    b.channel_type_name,
    b.channel_name,
    b.city_level,
    a.is_salvage, 
    a.is_75_city, 
    sum(a.clue_num) clue_num,
    sum(a.evaluate_num) evaluate_num,
    sum(a.onshelf_num) onshelf_num 
from clue_task_onshelf a
left join clue_info b on a.clue_id = b.clue_id
group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14
)
,

dau AS (
    SELECT
            dt,
            'other' AS toufang_type,
            'other' AS city_level,
            'other' AS channel_level,
			'other' AS channel_type_name,
            'other' AS channel_name_ctob,
			'other' as new_type ,
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
select 
    t1.dt, 
	t1.toufang_type, 
	t1.city_level,
    t1.channel_level, 
    t1.channel_type_name,
	t1.channel_name  as channel_name_ctob,
    t1.`圈车类型`, 
    t1.`首上架渠道`,
    t1.new_type,
    0 AS dau, 0 AS c1_dau,
    t1.clue_num, 
    t1.evaluate_num, 
    t1.onshelf_num, 
    t1.standard_onshelf_num,
    coalesce(q.quantity_set,0) quantity_set
from
(
select 
    a.dt, 
    a.channel_level, 
    a.toufang_type, 
    a.`圈车类型`, 
    a.`首上架渠道`,
    a.channel_level1,
    a.channel_level2,
    a.channel_type_name,
    a.channel_name,
    a.new_type,
    a.city_level,
    sum(case when a.is_salvage = 0 and a.is_75_city = '是' then a.clue_num else 0 end) as clue_num,
    sum(case when a.is_75_city = '是' then a.evaluate_num else 0 end) as evaluate_num,
    sum(case when a.cb_sale_type='tob' then a.onshelf_num else 0 end) as onshelf_num ,
ROUND(
    CAST(
        SUM(CASE WHEN a.cb_sale_type = 'tob' 
            THEN a.onshelf_num * COALESCE(t2_norm.single_listing_revenue_coef, t2_max.single_listing_revenue_coef) 
            ELSE 0 
        END) AS DECIMAL(20,4)
    ), 
4) AS standard_onshelf_num
from c1_channel a -- 和维度表关联过的线索量 工单量 上架量 
-- 规则1：正常判断 a.dt 是否落在 [start_date, end_date] 区间内
LEFT JOIN guazi_dw_import.dim_mkt_channel_listing_std_coef t2_norm 
       ON a.new_type = t2_norm.first_level_category
      AND a.dt >= t2_norm.start_date 
      AND a.dt <= t2_norm.end_date
-- 规则2：如果 a.dt 超出了该分类最大的 end_date，则匹配兜底表
LEFT JOIN coef_max t2_max 
       ON a.new_type = t2_max.first_level_category
      AND a.dt > t2_max.max_end_date
group by 1,2,3,4,5,6,7,8,9,10,11
) t1
left join (
    select 
        prepay_time, 
        channel_level, 
        toufang_type, 
        `圈车类型`, 
        `首上架渠道`,
        channel_level1,
        channel_level2,
        channel_type_name,
        channel_name,
        city_level,
        sum(quantity_set) quantity_set 
    from quantity_set_clue
    group by 1,2,3,4,5,6,7,8,9,10
) q  -- 净已定
on q.prepay_time = t1.dt 
and t1.channel_level = q.channel_level 
and t1.toufang_type = q.toufang_type
and coalesce(t1.`圈车类型`,'') = coalesce(q.`圈车类型`,'')
and coalesce(t1.`首上架渠道`,'') = coalesce(q.`首上架渠道`,'')
and coalesce(t1.channel_level1,'') = coalesce(q.channel_level1,'')
and coalesce(t1.channel_level2,'') = coalesce(q.channel_level2,'')
and coalesce(t1.channel_type_name,'') = coalesce(q.channel_type_name,'')
and coalesce(t1.channel_name,'') = coalesce(q.channel_name,'')
and coalesce(t1.city_level,'') = coalesce(q.city_level,'')

UNION ALL 

SELECT 
    dt,
    toufang_type,
    city_level,
    channel_level,
    channel_type_name,
    channel_name_ctob,
    '其他' AS `圈车类型`,     
    '其他' AS `首上架渠道`,   
	new_type ,
    dau,
    c1_dau,
    clue_num,
    evaluate_num,
    onshelf_num,
    standard_onshelf_num, 
    prepay_net_num
FROM dau;