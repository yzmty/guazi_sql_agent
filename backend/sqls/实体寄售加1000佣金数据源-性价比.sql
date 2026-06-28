/*
文件: 实体寄售加1000佣金数据源-性价比.sql
指标: 每天总上架量|每天总意向金量|每天_燃油_总上架量|每天_新能源_总上架量|每天_燃油_S+++上架量|每天_燃油_S++上架量|每天_燃油_S+上架量|每天_燃油_S上架量|每天_燃油_A上架量|每天_燃油_B上架量|每天_新能源_S+++上架量|每天_新能源_S++上架量|每天_新能源_S+上架量|每天_新能源_S上架量|每天_新能源_A上架量|每天_新能源_B上架量
业务: 实体寄售上架及意向金分析（按性价比分层）
场景: 实体寄售加佣金的实验复盘，统计实体寄售模式每天的上架量和意向金量，并按能源类型（燃油/新能源）和性价比等级（S+++/S++/S+/S/A/B）进行分层统计
标签: 实体寄售|上架|意向金|性价比|燃油|新能源|分层|C1|C2C
维度: 日期（上架日期或者意向金支付日期）
核心表: dw_car_platform_quality_supply_detail_ymd|dm_e_commerce_orders_detail_ymd
作者: 文国庆|杨悦芳
描述: 实体寄售上架量及意向金量统计，按性价比等级拆分，性价比等级是S+++/S+/S/A/B
*/
-- 上架意向金及性价比：just实体寄售
-- Save New Duplicate & Edit Just Text Twitter
WITH onshelf_base AS (
  -- 1. 取出实体寄售的单车上架明细及基础属性
  SELECT
    substr(cb_first_shelf_time, 1, 10) as dt,
    clue_id,
    case when fuel_type in (12, 13, 20) then '新能源' else '燃油' end as fuel_type,
    (CASE WHEN IF(cur_zhijia_protect_price > 0, ((dealer_undertake_car_price * 1.0) / cur_zhijia_protect_price), 1) < 0.85 THEN 'S+++' ELSE on_sale_level_desc END) as level_desc
  FROM guazi_dw_dw.dw_car_platform_quality_supply_detail_ymd
  WHERE dt between '${start_time}' AND '${date_y_m_d}'
    AND sku_type = 4 
    AND SUBSTRING(cb_first_shelf_time, 1, 10) = dt 
    AND INSTR(CONCAT(',', valid_tags, ','), ',1554,') >= 1 -- 实体寄售
),

onshelf_daily AS (
  -- 2. 将单车明细按天进行“行转列”统计 (多维度交叉组合)
  SELECT
    dt,
    count(distinct clue_id) as total_onshelf_cnt,                                   -- 每天总上架量
    
    -- 每天燃油+新能源大类汇总
    count(distinct case when fuel_type = '燃油' then clue_id end) as fuel_cnt,      
    count(distinct case when fuel_type = '新能源' then clue_id end) as nev_cnt,     

    -- 【燃油】+【性价比】组合拆分
    count(distinct case when fuel_type = '燃油' and level_desc = 'S+++' then clue_id end) as fuel_s3_cnt,
    count(distinct case when fuel_type = '燃油' and level_desc = 'S++' then clue_id end) as fuel_s2_cnt,
    count(distinct case when fuel_type = '燃油' and level_desc = 'S+' then clue_id end) as fuel_s1_cnt,
    count(distinct case when fuel_type = '燃油' and level_desc = 'S' then clue_id end) as fuel_s_cnt,
    count(distinct case when fuel_type = '燃油' and level_desc = 'A' then clue_id end) as fuel_a_cnt,
    count(distinct case when fuel_type = '燃油' and level_desc = 'B' then clue_id end) as fuel_b_cnt,

    -- 【新能源】+【性价比】组合拆分
    count(distinct case when fuel_type = '新能源' and level_desc = 'S+++' then clue_id end) as nev_s3_cnt,
    count(distinct case when fuel_type = '新能源' and level_desc = 'S++' then clue_id end) as nev_s2_cnt,
    count(distinct case when fuel_type = '新能源' and level_desc = 'S+' then clue_id end) as nev_s1_cnt,
    count(distinct case when fuel_type = '新能源' and level_desc = 'S' then clue_id end) as nev_s_cnt,
    count(distinct case when fuel_type = '新能源' and level_desc = 'A' then clue_id end) as nev_a_cnt,
    count(distinct case when fuel_type = '新能源' and level_desc = 'B' then clue_id end) as nev_b_cnt

  FROM onshelf_base
  GROUP BY dt
),

order_daily AS (
  -- 3. 按天统计实体寄售意向金量
  SELECT
    substr(buyer_order_pay_time, 1, 10) as dt,
    count(distinct order_id) as total_order_cnt
  FROM guazi_dw_dm.dm_e_commerce_orders_detail_ymd
  WHERE dt = '${date_y_m_d}' 
    AND substr(buyer_order_pay_time, 1, 10) between '${start_time}' AND '${date_y_m_d}' 
    AND c2c_type = 3 -- 实体寄售
  GROUP BY substr(buyer_order_pay_time, 1, 10)
)

-- 4. 最终拼接输出报表，保证空值为0
SELECT 
  COALESCE(t1.dt, t2.dt) AS `日期`,
  COALESCE(t1.total_onshelf_cnt, 0) AS `每天总上架量`, -- 实体寄售上架量
  COALESCE(t2.total_order_cnt, 0) AS `每天总意向金量`, -- 实体寄售意向金量
  
  -- 大盘数据
  COALESCE(t1.fuel_cnt, 0) AS `每天_燃油_总上架量`,
  COALESCE(t1.nev_cnt, 0) AS `每天_新能源_总上架量`,

  -- 燃油组合数据
  COALESCE(t1.fuel_s3_cnt, 0) AS `每天_燃油_S+++上架量`,
  COALESCE(t1.fuel_s2_cnt, 0) AS `每天_燃油_S++上架量`,
  COALESCE(t1.fuel_s1_cnt, 0) AS `每天_燃油_S+上架量`,
  COALESCE(t1.fuel_s_cnt, 0) AS `每天_燃油_S上架量`,
  COALESCE(t1.fuel_a_cnt, 0) AS `每天_燃油_A上架量`,
  COALESCE(t1.fuel_b_cnt, 0) AS `每天_燃油_B上架量`,

  -- 新能源组合数据
  COALESCE(t1.nev_s3_cnt, 0) AS `每天_新能源_S+++上架量`,
  COALESCE(t1.nev_s2_cnt, 0) AS `每天_新能源_S++上架量`,
  COALESCE(t1.nev_s1_cnt, 0) AS `每天_新能源_S+上架量`,
  COALESCE(t1.nev_s_cnt, 0) AS `每天_新能源_S上架量`,
  COALESCE(t1.nev_a_cnt, 0) AS `每天_新能源_A上架量`,
  COALESCE(t1.nev_b_cnt, 0) AS `每天_新能源_B上架量`

FROM onshelf_daily t1
FULL OUTER JOIN order_daily t2 ON t1.dt = t2.dt
ORDER BY `日期`;