/*
文件: 数据源1-截面数据（加圈车，首上架，标准上架）.sql
指标: dau|C1_dau|clue_num（线索量）|evaluate_num（工单量）|onshelf_num（上架量）|standard_onshelf_num（标准上架量）|prepay_net_num（净已定量）
业务: C1线索转化全链路分析（含圈车类型和首上架渠道）
场景: 用于旧日报，按日期、投放类型、城市等级、渠道层级、渠道类型、圈车类型、首上架渠道统计C1车源的DAU、线索量、工单量、上架量、标准上架量、净已定量，用于全链路转化分析
标签: 线索|工单|上架|标准上架|净已定|DAU|C1|渠道|投放|圈车|首上架|转化漏斗
维度: dt（日期）|toufang_type（投放类型）|city_level（城市等级）|channel_level（渠道层级）|channel_type_name（渠道类型）|channel_name_ctob（渠道名称）|圈车类型|首上架渠道|new_type（新渠道分类）
核心表: dm_ctob_clue_detail_transform_csd_inc_ymd|dwd_ctob_top_channel_all_info_ymd|dim_com_city_ymd|dw_ctob_c1_car_source_ymd|dm_ctob_tableau_total_index_stat_ymd
作者: 未知
描述: 按渠道、投放、圈车类型、首上架渠道统计C1线索量、工单量、上架量、标准上架量、净已定量
*/
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

channel AS (
    SELECT 
          ca_s, ca_n
         ,CASE WHEN channel_label_ch_name LIKE '%非投放%' THEN '非投放'
               WHEN line_id IN ('2','3') THEN '投放'
            ELSE COALESCE(toufang_type,'非投放') END AS toufang_type
         ,channel_type_name_ctob AS channel_type_name
         ,customer_type_ch_name AS customer_type_name
         ,phone_system_ch_name AS phone_system
         ,new_channel_ch_name AS new_channel
         ,customer_type
         ,agent_ch_name AS agent
         ,channel_name_ctob
         ,channel_tag_id
         ,channel_tag
         ,line_id
         ,channel_level1
         ,channel_level2
    FROM guazi_dw_dwd.dwd_ctob_top_channel_all_info_ymd
    WHERE dt = '${date_y_m_d}'  
),

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


SELECT 
    dt,
    toufang_type,
    city_level,
    CASE 
        WHEN channel_level2 = '非主端' THEN '非主端-端产品'
        WHEN channel_level2 = '直投' THEN '表单'
        WHEN channel_level1 = '商务拓展' THEN '商务'
        WHEN channel_level1 = '端产品' THEN '主端'
        ELSE channel_level1 
    END AS channel_level,
    CASE WHEN channel_type_name_wide IS NULL THEN '无归因' ELSE channel_type_name_wide END AS channel_type_name,
    CASE WHEN channel_name IS NULL THEN '无归因' ELSE channel_name END AS channel_name_ctob,
    `圈车类型`,     
    `首上架渠道`,   
	new_type ,
    0 AS dau, 0 AS c1_dau,
    SUM(CASE WHEN is_salvage = 0 AND is_75_city = '是' THEN clue_num ELSE 0 END) AS clue_num,
    SUM(CASE WHEN is_75_city = '是' THEN evaluate_num ELSE 0 END) AS evaluate_num,
    SUM(CASE WHEN cb_sale_type='tob' THEN onshelf_num ELSE 0 END) AS onshelf_num,
    SUM(CASE WHEN cb_sale_type='tob' THEN onshelf_num * ratio_coeff ELSE 0 END) AS standard_onshelf_num,
    (SUM(deliver_num) - SUM(refund_num)) AS prepay_net_num
FROM (
		select 
			*,
	        CASE 
			WHEN channel_level2 = '主端' AND toufang_type = '非投放' AND customer_type_name = 'App' THEN 1
			WHEN channel_level2 = '主端' AND toufang_type = '投放' AND customer_type_name = 'App' THEN 0.85
			WHEN channel_level2 = '主端' AND toufang_type = '非投放' AND customer_type_name = '小程序' THEN 0.97
			WHEN channel_level2 = '主端' AND toufang_type = '投放' AND customer_type_name = '小程序' THEN 0.85
			WHEN channel_level2 = '非主端' AND toufang_type = '非投放' AND customer_type_name = 'App' THEN 0.95
			WHEN channel_level2 = '非主端' AND toufang_type = '非投放' AND customer_type_name = '小程序' THEN 1.02
			WHEN channel_level2 = '非主端' AND toufang_type = '投放' AND customer_type_name = 'App' THEN 0.93
			WHEN channel_level2 = '非主端' AND toufang_type = '投放' AND customer_type_name = '小程序' THEN 0.79
			WHEN channel_level1 = '非端产品' THEN 0.70
			WHEN channel_level1 = '商务拓展' THEN 0.44
			WHEN channel_level1 = '直播' THEN 0.51
			WHEN CASE WHEN ca_s = 'sop_zijianxiansuo' THEN '网销自建' WHEN ctob_busi_type_code IN ('3','7') THEN 'B2B' ELSE COALESCE(channel_type_name,'瓜子二手车') END = '网销自建' THEN 0.88 
			ELSE 0.82 
		END AS ratio_coeff
			, case 
			when  channel_level2 = '主端' and toufang_type = '非投放' and customer_type_name = 'App' then '主端-非投放-App'
			when  channel_level2 = '主端' and toufang_type = '投放' and customer_type_name = 'App' then '主端-投放-App'
			when  channel_level2 = '主端' and toufang_type = '非投放' and customer_type_name = '小程序' then '主端-非投放-小程序'
			when  channel_level2 = '主端' and toufang_type = '投放' and customer_type_name = '小程序' then '主端-投放-小程序'
			when  channel_level2 = '非主端' and toufang_type = '非投放' and customer_type_name = 'App' then '非主端-非投放-App'
			when  channel_level2 = '非主端' and toufang_type = '非投放' and customer_type_name = '小程序' then '非主端-非投放-小程序'
			when  channel_level2 = '非主端' and toufang_type = '投放' and customer_type_name = 'App' then '非主端-投放-App'
			when  channel_level2 = '非主端' and toufang_type = '投放' and customer_type_name = '小程序' then '非主端-投放-小程序'
			when  channel_level1 = '非端产品' then '非端产品'
			when  channel_level1 = '商务拓展' then '商务拓展'
			when  channel_level1 = '直播' then '直播'
			when  case when ca_s = 'sop_zijianxiansuo' then '网销自建' when ctob_busi_type_code in ('3','7') then 'B2B' else coalesce(channel_type_name,'瓜子二手车') end = '网销自建' then '网销自建'
			else '其他' end as new_type
		from
		(SELECT 
			a.dt, a.clue_id, a.is_salvage, a.is_75_city, a.cb_sale_type, c.city_level, a.ca_s ,
			d.`圈车类型`,  
			d.`首上架渠道`, 
			COALESCE(clue_num,0) AS clue_num,
			COALESCE(evaluate_num,0) AS evaluate_num,
			COALESCE(onshelf_num,0) AS onshelf_num,
			COALESCE(a.deliver_num,0) AS deliver_num,
			COALESCE(a.refund_num,0) AS refund_num,
			CASE WHEN attribution_type=1 THEN '投放' WHEN attribution_type=2 THEN '非投放' ELSE COALESCE(b.toufang_type,'非投放') END AS toufang_type,
			CASE WHEN a.ca_s = 'sop_zijianxiansuo' THEN '网销自建' WHEN a.ctob_busi_type_code IN ('3','7') THEN 'B2B' ELSE COALESCE(b.channel_type_name,'瓜子二手车') END AS channel_type_name_wide,
			CASE WHEN a.ca_s = 'sop_zijianxiansuo' THEN '网销自建' ELSE b.channel_name_ctob END AS channel_name,
			CASE WHEN a.ca_s = 'sop_zijianxiansuo'  THEN '端产品' 
				   WHEN a.ctob_busi_type_code IN ('3','7') THEN 'B2B'
				   ELSE COALESCE(channel_level1,'端产品') END AS channel_level1,
			CASE WHEN a.ca_s = 'sop_zijianxiansuo'  THEN '主端' 
				   WHEN a.ctob_busi_type_code IN ('3','7') THEN 'B2B'
				   ELSE COALESCE(channel_level2,'主端') END AS channel_level2,
			b.channel_type_name,
			b.channel_name_ctob,
			b.customer_type_name
			,a.ctob_busi_type_code
		
		FROM clue_task_onshelf a
		LEFT JOIN channel b ON a.ca_s = b.ca_s AND a.ca_n = b.ca_n 
		LEFT JOIN city c ON a.city_name = c.city_name
	   
		LEFT JOIN car_source_dim d ON a.clue_id = d.clue_id AND a.dt = d.dt  ) tt
) t
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8 ,9

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