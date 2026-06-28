/*
指标: 线索量total_cnt|有车主心理底价线索量base_price_cnt|车主预期偏离度
业务: C1车源车主预期偏离度分析
场景: 统计C1车源按圈车类型、首上架渠道的车主预期偏离度（车主原始心理底价/上架时车主到手模型价），用于分析不同渠道车源的价格预期差异
标签: 截面|圈车|车主预期|偏离度|底价|模型价|C1|首上C2B|价格分析|经营周报|首上架
维度: dt|圈车类型|首上架渠道
核心表: dw_ctob_c1_car_source_ymd|dim_ctob_auction_car_source_ymd
作者：文国庆
描述: 获取车主原始心理底价和上架时车主到手模型价，计算车主预期偏离度 = org_base_price / seller_model_price
*/
-- C圈车首上C2B & B圈车首上C2B 的车主预期（clue_id维度）
WITH car_tag AS (
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
    WHERE t1.dt = '${date_y_m_d}' 
      AND t1.is_c1_clue = 1 
      AND SUBSTR(onshelf_time, 1, 10) >= '${start_date}' 
)

SELECT
	dt,
	`圈车类型`,
	`首上架渠道`,
	count(distinct clue_id) total_cnt,
	count(distinct case when org_base_price > 0 and seller_model_price > 0 then clue_id end) base_price_cnt,
	sum(case when org_base_price > 0 and seller_model_price > 0 then `车主预期偏离度` end) `车主预期偏离度`
FROM
(SELECT 
    c.dt,
    c.clue_id,
    c.`圈车类型`,
    c.`首上架渠道`,
    case when org_base_price > 0 then 1 else 0 end as has_org_base_price,
    org_base_price, --  `车主原始心理底价`,
    seller_model_price, --  `上架时车主到手模型价`,
    org_base_price * 1.0 / nullif(seller_model_price, 0) as `车主预期偏离度`
FROM car_tag c
LEFT JOIN guazi_dw_dwd.dim_ctob_auction_car_source_ymd p ON c.clue_id = p.clue_id 
where  p.dt = '${date_y_m_d}'
AND p.ctob_busi_type_code IN (1)
-- AND c.`圈车类型` = 'C圈车'  -- 只要首上C2B的
 ) t
 group by 1,2,3
 order by 1,2,3
