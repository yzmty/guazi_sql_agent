/*
文件: 经营-截面1-圈车和上架.sql
指标: 上架车源数onshelf_num|标准上架车源数
业务: C1圈车渠道标准上架车源数统计
场景: 按圈车类型和首上架渠道统计上架车源数，并根据渠道归因类型匹配标准系数折算标准上架车源数
标签: 截面|圈车|上架车源数|标准上架车源数|标准上架|C1|渠道|系数|市场|市场渠道|市场系数|经营周报|首上架
维度: dt|圈车类型|首上架渠道|市场渠道type_level_1
核心表: dm_ctob_clue_detail_transform_csd_inc_ymd|dwd_ctob_top_channel_all_info_ymd|dim_com_city_ymd|dw_ctob_c1_car_source_ymd|dim_mkt_channel_listing_std_coef
作者: 文国庆
描述: 通过线索转化表关联渠道信息、城市等级、圈车类型及首上架渠道，汇总上架车源数，再匹配渠道标准系数折算为标准上架车源数
*/
WITH clue_task_onshelf AS (
    SELECT *
    FROM guazi_dw_dm.dm_ctob_clue_detail_transform_csd_inc_ymd     
    WHERE dt BETWEEN '${start}' AND '${date_y_m_d}' 
      AND ctob_busi_type_code IN (0,1)
),
channel AS (
    SELECT 
        ca_s, ca_n,
        CASE WHEN channel_label_ch_name LIKE '%非投放%' THEN '非投放'
             WHEN line_id IN ('2','3') THEN '投放'
             ELSE coalesce(toufang_type,'非投放') 
        END AS toufang_type,
        channel_type_name_ctob AS channel_type_name,
        customer_type_ch_name AS customer_type_name,
        phone_system_ch_name AS phone_system,
        new_channel_ch_name AS new_channel,
        customer_type,
        agent_ch_name AS agent,
        channel_name_ctob, channel_tag_id, channel_tag,
        line_id, channel_level1, channel_level2
    FROM guazi_dw_dwd.dwd_ctob_top_channel_all_info_ymd
    WHERE dt = '${date_y_m_d}'  
      AND channel_level1 != 'B2B'
),
city AS (
    SELECT city_id, city_name, short_name, domain, city_level, province_name, province_short_name
    FROM guazi_dw_dwd.dim_com_city_ymd
    WHERE dt = '${date_y_m_d}'
),
total AS (
    SELECT 
        dt, toufang_type, city_level,
        CASE WHEN channel_level2 = '非主端' THEN '非主端-端产品'
             WHEN channel_level2 = '直投' THEN '表单'
             WHEN channel_level1 = '商务拓展' THEN '商务'
             WHEN channel_level1 = '端产品' THEN '主端'
             ELSE channel_level1 END AS channel_level,
        customer_type_name, channel_level2, channel_level1,
        CASE WHEN channel_type_name_wide IS NULL THEN '无归因' ELSE channel_type_name_wide END AS channel_type_name,
        CASE WHEN channel_name IS NULL THEN '无归因' ELSE channel_name END AS channel_name_ctob,
        `圈车类型`, `首上架渠道`,
        0 AS dau, 0 AS c1_dau,
        SUM(CASE WHEN is_salvage = 0 AND is_75_city = '是' THEN clue_num ELSE 0 END) AS clue_num,
        SUM(CASE WHEN is_75_city = '是' THEN evaluate_num ELSE 0 END) AS evaluate_num,
        SUM(CASE WHEN cb_sale_type = 'tob' THEN onshelf_num ELSE 0 END) AS onshelf_num,
        (SUM(deliver_num) - SUM(refund_num)) AS prepay_net_num
    FROM (
        SELECT 
            a.dt, a.clue_id, a.is_salvage, a.is_75_city, a.cb_sale_type, c.city_level,
            COALESCE(clue_num, 0) AS clue_num,
            COALESCE(evaluate_num, 0) AS evaluate_num,
            COALESCE(onshelf_num, 0) AS onshelf_num,
            COALESCE(a.deliver_num, 0) AS deliver_num,
            COALESCE(a.refund_num, 0) AS refund_num,
            CASE WHEN attribution_type = 1 THEN '投放' WHEN attribution_type = 2 THEN '非投放' ELSE COALESCE(b.toufang_type,'非投放') END AS toufang_type,
            CASE WHEN a.ca_s = 'sop_zijianxiansuo' THEN '网销自建' WHEN a.ctob_busi_type_code IN ('3','7') THEN 'B2B' ELSE COALESCE(b.channel_type_name,'瓜子二手车') END AS channel_type_name_wide,
            CASE WHEN a.ca_s = 'sop_zijianxiansuo' THEN '网销自建' ELSE b.channel_name_ctob END AS channel_name,
            CASE WHEN a.ca_s = 'sop_zijianxiansuo' THEN '端产品' WHEN a.ctob_busi_type_code IN ('3','7') THEN 'B2B' ELSE COALESCE(channel_level1,'端产品') END AS channel_level1,
            CASE WHEN a.ca_s = 'sop_zijianxiansuo' THEN '主端' WHEN a.ctob_busi_type_code IN ('3','7') THEN 'B2B' ELSE COALESCE(channel_level2,'主端') END AS channel_level2,
            b.channel_type_name, b.channel_name_ctob, b.customer_type_name, d.`圈车类型`, d.`首上架渠道`
        FROM clue_task_onshelf a
        LEFT JOIN channel b ON a.ca_s = b.ca_s AND a.ca_n = b.ca_n 
        LEFT JOIN city c ON a.city_name = c.city_name
        LEFT JOIN (
            SELECT DISTINCT 
                SUBSTR(onshelf_time, 1, 10) AS dt,
                CASE WHEN car_collect_platform IN (2,3) OR consign_choose_type IN (1, 2) THEN 'C圈车' ELSE 'B圈车' END AS `圈车类型`,
                CASE WHEN first_onshelf_biz_line = 'C2C独售-虚拟' THEN '首上虚拟寄售'
                     WHEN first_onshelf_biz_line = 'C2C独售-门店' THEN '首上实体寄售'
                     WHEN first_onshelf_biz_line = 'C2B' THEN '首上C2B'
                     WHEN first_onshelf_biz_line = '自营C' THEN '首上自营C'
                     WHEN first_onshelf_biz_line = '自营B' THEN '首上自营B'
                     ELSE first_onshelf_biz_line END AS `首上架渠道`,
                t1.clue_id
            FROM guazi_dw_dw.dw_ctob_c1_car_source_ymd t1
            WHERE t1.dt = '${date_y_m_d}' AND t1.is_c1_clue = 1 AND SUBSTR(onshelf_time, 1, 10) IS NOT NULL 
        ) d ON a.clue_id = d.clue_id
    ) t
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
-- 将 final select 中的 type_level_1 逻辑提前处理，方便下游关联
total_with_type AS (
    SELECT 
        dt, `圈车类型`, `首上架渠道`, 
        CASE 
            WHEN channel_level2 = '主端' AND toufang_type = '非投放' AND customer_type_name = 'App' THEN '主端-非投放-APP'
            WHEN channel_level2 = '主端' AND toufang_type = '投放' AND customer_type_name = 'App' THEN '主端-投放-APP'
            WHEN channel_level2 = '主端' AND toufang_type = '非投放' AND customer_type_name = '小程序' THEN '主端-非投放-小程序'
            WHEN channel_level2 = '主端' AND toufang_type = '投放' AND customer_type_name = '小程序' THEN '主端-投放-小程序'
            WHEN channel_level2 = '非主端' AND toufang_type = '非投放' AND customer_type_name = 'App' THEN '非主端-非投放-APP'
            WHEN channel_level2 = '非主端' AND toufang_type = '非投放' AND customer_type_name = '小程序' THEN '非主端-非投放-小程序'
            WHEN channel_level2 = '非主端' AND toufang_type = '投放' AND customer_type_name = 'App' THEN '非主端-投放-APP'
            WHEN channel_level2 = '非主端' AND toufang_type = '投放' AND customer_type_name = '小程序' THEN '非主端-投放-小程序'
            WHEN channel_level1 = '非端产品' THEN '非端产品'
            WHEN channel_level1 = '商务拓展' THEN '商务拓展'
            WHEN channel_level1 = '直播' THEN '直播'
            WHEN channel_type_name = '网销自建' THEN '网销自建' 
            ELSE '其他'  
        END AS type_level_1,sum(onshelf_num) as onshelf_num
    FROM total
	group by 1,2,3,4
	HAVING SUM(onshelf_num) > 0
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

-- 最终查询计算
SELECT 
    t1.dt,
    t1.`圈车类型`,
    t1.`首上架渠道`,
    t1.type_level_1,
    -- 核心匹配逻辑展现：如果区间内匹配到了，就用区间的；如果没匹配到且超期了，就用最大的那条
    t1.onshelf_num AS `上架车源数`,
	t1.onshelf_num * COALESCE(t2_norm.single_listing_revenue_coef, t2_max.single_listing_revenue_coef) as `标准上架车源数`
FROM total_with_type t1
-- 规则1：正常判断 t1.dt 是否落在 [start_date, end_date] 区间内
LEFT JOIN guazi_dw_import.dim_mkt_channel_listing_std_coef t2_norm 
       ON t1.type_level_1 = t2_norm.first_level_category
      AND t1.dt >= t2_norm.start_date 
      AND t1.dt <= t2_norm.end_date
-- 规则2：如果 t1.dt 超出了该分类最大的 end_date，则匹配兜底表
LEFT JOIN coef_max t2_max 
       ON t1.type_level_1 = t2_max.first_level_category
      AND t1.dt > t2_max.max_end_date
