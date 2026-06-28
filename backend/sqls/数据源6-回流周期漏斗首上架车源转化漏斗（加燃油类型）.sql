/*
文件: 数据源6-回流周期漏斗首上架车源转化漏斗.sql
指标: 新上架车源量|T0已定量|T1累计已定量|T3累计已定量|T5累计已定量|T7累计已定量|T14累计已定量|T21累计已定量|T35累计已定量|T60累计已定量
业务: 首上架车源（非回流车源）的cohort转化分析
场景: 按首上架日期统计非回流C1车源在不同时间窗口（T0~T60天）的累计已定量，区分自营C/自营B/C2C独售/C2B等上架类型，用于分析首上架车源的转化效率
标签: 首上架|回流|Cohort|转化|已定量|自营C|自营B|C2C|C2B|燃油|新能源
维度: dt（首上架日期）|shelf_type（上架类型）|selling_channel（售出渠道）|fuel_type（能源类型）
核心表: dim_ctob_auction_car_source_ymd|dw_car_platform_quality_supply_detail_ymd|dwb_cars_car_source_tag_day|dm_ctob_clue_detail_transform_csd_inc_ymd|dwb_ctob_trade_order_day|dwd_ctob_car_owner_clue_transform_ymd
作者: 未知
描述: 统计非回流C1首上架车源在T0~T60天的已定量，按上架类型和售出渠道拆分
*/
-- 数据源6：回流周期漏斗首上架车源转化漏斗
-- 所谓第一台车 第二台车是对于自营而言，自营收车的车源是第一台车，自营上架的车是第二台车
WITH changetable AS (
          SELECT
            clue_id as c2b_clue_id,  -- 车源id（收车）
            sale_clue_id as clue_id  -- 上架后车源id（上架）
          FROM guazi_dw_dwb.dwb_ctob_trade_order_day  -- 订单主表
          WHERE sale_clue_id > 0  -- 上架后车源id > 0
          AND dt = '${date_y_m_d}'
),
self_shelf AS (
     SELECT 
          a.clue_id -- 第二台车 （上架）
          ,c2b_clue_id  -- （收车）
          ,ctob_busi_type_code
     FROM 
          (
               SELECT 
                    t1.clue_id -- 第二台车 （上架）
                    ,t2.c2b_clue_id -- 第一台车ID （收车）车源
                    ,ctob_busi_type_code
               FROM 
               (
                    SELECT
                         clue_id, -- 第二台车 （上架）
                         ctob_busi_type_code  -- 拍卖业务类型：0:其他 1:C线索 2:经销商C线索 3:经销商B线索 4:开放平台 5:斩仓车 6:淘车 7:B2C同售B2B 8:B2C满7天自动同售B2B 9 B收车 10C收车
                    FROM   guazi_dw_dwd.dwd_ctob_car_owner_clue_transform_ymd  -- ctob-车主-线索来源渠道转化明细
                    WHERE dt = '${date_y_m_d}' 
                    AND ctob_busi_type_code IN (9,10)
               )t1 -- 上架
               LEFT JOIN changetable t2 ON t1.clue_id = t2.clue_id
          )a  
)
,tb_onshelf_time as
( 
			SELECT
            clue_id
            ,SUBSTRING(onshelf_time, 1, 10) AS dt -- B端上架时间
		      ,case when fuel_type in (12,13,20) then '新能源' else '燃油车' end as fuel_type 
            ,ctob_busi_type_code  -- 拍卖业务类型：0:其他 1:C线索 2:经销商C线索 3:经销商B线索 4:开放平台 5:斩仓车 6:淘车 7:B2C同售B2B 8:B2C满7天自动同售B2B 9 B收车 10C收车
        FROM guazi_dw_dwd.dim_ctob_auction_car_source_ymd  -- B端车源信息维表
        WHERE dt = '${date_y_m_d}'
        AND ctob_busi_type_code IN (0,1,9,10) -- 所有C1新上架量

        union all -- C收车在C上架
	
        select 
            clue_id
           ,substring(create_time,1,10) dt -- 上架时间
				,case when fuel_type in (12,13,20) then '新能源' else '燃油车' end as fuel_type

            ,10 ctob_busi_type_code
		
        from guazi_dw_dw.dw_car_platform_quality_supply_detail_ymd  -- toc售卖车源明细
        where dt = '${date_y_m_d}'
        and create_time is not null 
        and clue_id in 
        (
        select clue_id from self_shelf where ctob_busi_type_code = 10 -- C收车
        )
),
clue_c2c AS (
  SELECT
    clue_id
    ,SUBSTRING(created_at, 1, 10) AS create_dt
  FROM guazi_dw_dwb.dwb_cars_car_source_tag_day -- 车源标签表
  WHERE dt = DATE_SUB(CURRENT_DATE, 1) 
  AND tag IN (1564,1580)
  group by 1,2
)


SELECT
    m.dt
    ,case when m.label='C自营' then 'C自营' 
          when m.label='B自营' then 'B自营'
          when m.shelf_type = 'C2C独售' then 'C2C独售' else 'C2B' end as shelf_type
    ,n.selling_channel -- 在哪个渠道售出
	,m.fuel_type
    ,COUNT(DISTINCT m.clue_id) AS `新上架车源量`
    ,COUNT(DISTINCT CASE WHEN n.dt = m.dt THEN n.clue_id END) AS `T0已定量`
    ,COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 1 DAY) THEN n.clue_id END) AS `T1累计已定量`
    ,COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 3 DAY) THEN n.clue_id END) AS `T3累计已定量`
    ,COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 5 DAY) THEN n.clue_id END) AS `T5累计已定量`
    ,COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 7 DAY) THEN n.clue_id END) AS `T7累计已定量`
    ,COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 14 DAY) THEN n.clue_id END) AS `T14累计已定量`
    ,COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 21 DAY) THEN n.clue_id END) AS `T21累计已定量`
    ,COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 35 DAY) THEN n.clue_id END) AS `T35累计已定量`
    ,COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 60 DAY) THEN n.clue_id END) AS `T60累计已定量`
FROM
(
        SELECT
            t1.dt
            ,t1.clue_id
				 ,fuel_type
            ,CASE WHEN t2.clue_id IS NOT NULL THEN 'C2C独售' ELSE '其他' END AS shelf_type
            ,CASE WHEN  t1.ctob_busi_type_code not in (9,10) THEN '非自营'  when t1.ctob_busi_type_code =9 then 'B自营' when t1.ctob_busi_type_code =10 then 'C自营' END AS label
        FROM
        (
            SELECT
                clue_id
                ,min(dt) dt 
                ,ctob_busi_type_code
						,fuel_type
            FROM tb_onshelf_time a  
            group by clue_id,
                    ctob_busi_type_code,fuel_type
        )t1
        LEFT JOIN clue_c2c t2 on t1.clue_id = t2.clue_id AND t1.dt= t2.create_dt
        LEFT JOIN self_shelf t3 ON t1.clue_id = t3.c2b_clue_id  --第一台车
        where t3.c2b_clue_id is  null    
        and  t1.dt BETWEEN '${start}' AND '${date_y_m_d}'
   
)m
LEFT JOIN
(
    SELECT         
          dt
          ,clue_id
          ,CASE WHEN ctob_busi_type_code = 9 AND  ctob_deal_busi_code = 1 THEN 'B_purchase_B_sale'        
                WHEN ctob_busi_type_code IN (0,1) AND  ctob_deal_busi_code in(1,5) THEN 'C2B' 
               WHEN ctob_busi_type_code = 10 AND  ctob_deal_busi_code <> 3 THEN 'C_purchase_B_sale'         
               WHEN ctob_busi_type_code = 10 AND  ctob_deal_busi_code = 3 THEN 'C_purchase_C_sale'
              WHEN ctob_busi_type_code IN (0,1) and ctob_deal_busi_code = 3 THEN 'C2C' else  concat(ctob_busi_type_code,'',ctob_deal_busi_code) END AS selling_channel -- 售卖渠道
     FROM guazi_dw_dm.dm_ctob_clue_detail_transform_csd_inc_ymd         
     WHERE dt between '${start}' and '${date_y_m_d}'           
     AND ctob_busi_type_code in (0,1,9,10) -- 一口价线索         
     AND ctob_deal_busi_code in (1,3,4,5,7)  -- 1C2B 3C2C 4C收车 7B收车'          
     AND deliver_num >0 -- 已定        
     AND clue_id is not null        
     GROUP BY 1,2,3
)n ON m.clue_id = n.clue_id and m.dt <= n.dt

GROUP BY 1,2,3,4
-- ORDER BY m.dt DESC, m.shelf_type