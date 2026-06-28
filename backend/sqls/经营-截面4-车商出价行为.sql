/*
文件: 经营-截面4-车商出价行为.sql
指标: 出价车源量|到价车源量|出价车商规模|出价车商车源|出价深度|出价次数
业务: C1车源车商出价行为分析
场景: 统计C1车源按圈车类型、首上架渠道的车商出价行为指标，包括出价车源量、到价车源量、出价车商规模、出价车商车源、出价深度、出价次数，用于分析不同渠道车源的拍卖活跃度和车商参与度
标签: 截面|圈车|车商出价|出价深度|到价|拍卖|秒杀|明暗拍|C1|首上C2B|经营周报|车商|首上架
维度: dt|圈车类型|首上架渠道
核心表: dw_ctob_c1_car_source_ymd|dwd_ctob_auction_bid_ymd|dwd_ctob_auction_bid_log_inc_ymd
作者: 文国庆
描述: 获取C1车源的车商出价行为指标，包括出价车源量、到价车源量、出价车商规模、出价车商车源、出价深度、出价次数
*/
-- 车商出价行为（按天、圈车类型、首上架渠道维度聚合）
WITH bid_data AS (
    SELECT 
        clue_id,
        dt,
        deal_user_id,
        bid_deep,
        rn
    FROM (
        -- 秒杀
        SELECT
            clue_id,
            deal_user_id,
            substr(bid_create_time, 1, 10) AS dt,
            CASE WHEN auction_type = 103 AND bid_seller_price > 0 THEN bid_amount * 1.0000 / bid_seller_price
                 ELSE 0 END AS bid_deep,
            row_number() OVER(PARTITION BY clue_id, substr(bid_create_time, 1, 10) ORDER BY bid_amount DESC) AS rn
        FROM guazi_dw_dwd.dwd_ctob_auction_bid_ymd
        WHERE dt = '${date_y_m_d}'
          AND substr(bid_create_time, 1, 10) BETWEEN '${start}' AND '${date_y_m_d}'
          AND auction_type = 103
          AND ctob_busi_type_code IN (1,9)
		  AND bid_type <> 18

        UNION ALL

        -- 明暗拍
        SELECT
            clue_id,
            deal_user_id,
            substr(auction_end_time, 1, 10) AS dt,
            CASE WHEN auction_type IN (102, 105, 106, 110) AND model_price > 0 THEN bid_amount * 1.0000 / model_price
                 ELSE 0 END AS bid_deep,
            row_number() OVER(PARTITION BY clue_id, substr(auction_end_time, 1, 10) ORDER BY bid_amount DESC) AS rn
        FROM guazi_dw_dwd.dwd_ctob_auction_bid_ymd
        WHERE dt = '${date_y_m_d}'
          AND substr(auction_end_time, 1, 10) BETWEEN '${start}' AND '${date_y_m_d}'
          AND auction_type IN (102, 105, 106, 110)
          AND ctob_busi_type_code IN (1,9)
    ) t
),
bid_data_total as (
SELECT
	dt,
	clue_id,
	user_id,
	sum(bid_cnt) bid_cnt
FROM
(SELECT
  substr(bid_time, 1, 10) dt,
 	clue_id,
 	user_id,
	1 as bid_cnt
FROM
  guazi_dw_dwd.dwd_ctob_auction_bid_log_inc_ymd
WHERE
  dt BETWEEN '${start}' AND '${date_y_m_d}'
  AND substr(bid_time, 1, 10) BETWEEN '${start}' AND '${date_y_m_d}'
  AND auction_type = 103
  AND ctob_busi_type_code IN (1,9)
  AND bid_type <> 18

	UNION ALL

SELECT
  substr(auction_open_time, 1, 10) dt,
 	clue_id,
 	user_id,
	1 as bid_cnt
FROM
  guazi_dw_dwd.dwd_ctob_auction_bid_log_inc_ymd
WHERE
  dt BETWEEN '${start}' AND '${date_y_m_d}'
  AND substr(auction_open_time, 1, 10) BETWEEN '${start}' AND '${date_y_m_d}'
  AND auction_type IN (102, 105, 106, 110)
  AND ctob_busi_type_code IN (1,9)
 ) t
group by 1,2,3
)
,car_source AS (
    SELECT DISTINCT 
        SUBSTR(onshelf_time, 1, 10) AS onshelf_dt,
        CASE WHEN car_collect_platform IN (2, 3) OR consign_choose_type IN (1, 2) THEN 'C圈车' ELSE 'B圈车' END AS `圈车类型`,
        CASE WHEN first_onshelf_biz_line = 'C2C独售-虚拟' THEN '首上虚拟寄售'
             WHEN first_onshelf_biz_line = 'C2C独售-门店' THEN '首上实体寄售'
             WHEN first_onshelf_biz_line = 'C2B' THEN '首上C2B'
             WHEN first_onshelf_biz_line = '自营C' THEN '首上自营C'
             WHEN first_onshelf_biz_line = '自营B' THEN '首上自营B'
             ELSE first_onshelf_biz_line END AS `首上架渠道`,
        clue_id
    FROM guazi_dw_dw.dw_ctob_c1_car_source_ymd
    WHERE dt = '${date_y_m_d}' 
      AND is_c1_clue = 1 
      AND SUBSTR(onshelf_time, 1, 10) is not null
)

SELECT
	t1.*,
	t2.bid_cnt as `出价次数`

FROM
(SELECT 
    b.dt,
    c.`圈车类型`,
    c.`首上架渠道`,
    COUNT(DISTINCT b.clue_id) AS `出价车源量`,
	  COUNT(DISTINCT CASE WHEN b.rn = 1 and b.bid_deep > 1.0 THEN b.clue_id END) AS `到价车源量`,
    COUNT(DISTINCT b.deal_user_id) AS `出价车商规模`,
    COUNT(DISTINCT CONCAT(CAST(b.clue_id AS VARCHAR), CAST(b.deal_user_id AS VARCHAR))) AS `出价车商车源`,
    avg(case when b.rn = 1 then b.bid_deep end) AS `出价深度`
FROM bid_data b
LEFT JOIN car_source c ON b.clue_id = c.clue_id
GROUP BY 1,2,3
ORDER BY 1,2,3
) t1
LEFT JOIN (
SELECT
	t1.dt,
	t2.`圈车类型`,
	t2.`首上架渠道`,
	sum(t1.bid_cnt) as bid_cnt
FROM bid_data_total t1
LEFT JOIN car_source t2 on t1.clue_id = t2.clue_id
GROUP BY 1,2,3
ORDER BY 1,2,3
) t2 on t1.dt = t2.dt and t1.`圈车类型` = t2.`圈车类型` and t1.`首上架渠道` = t2.`首上架渠道`
WHERE t1.`首上架渠道` = '首上C2B'
order by dt 

