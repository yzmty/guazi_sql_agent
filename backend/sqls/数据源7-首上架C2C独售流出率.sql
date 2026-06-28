/*
文件: 数据源7-首上架C2C独售流出率.sql
指标: 新上架车源量|回流车源量|T0回流量|T1累计回流量|T3累计回流量|T5累计回流量|T7累计回流量|T14累计回流量|T21累计回流量|T35累计回流量|T60累计回流量
业务: 首上架C2C独售流出率分析
场景: 统计首上C2C在后续不同时间窗口（T0~T60天）发生回流（二次上架）的累计量，区分自营C/自营B/C2C独售/C2B等上架类型
标签: 首上架|回流|周期|Cohort|转化|自营C|自营B|C2C|C2B
维度: dt（首上架日期）|shelf_type（上架类型）
核心表: dim_ctob_auction_car_source_ymd|dw_car_platform_quality_supply_detail_ymd|dwb_cars_car_source_tag_day|dw_ctob_auction_car_source_statistic_ymd|dwb_ctob_trade_order_day|dwd_ctob_car_owner_clue_transform_ymd
作者: 未知
描述: 统计首上C2C车源在T0~T60天的累计回流量，按上架类型拆分
*/
-- 数据源7：回流周期
WITH changetable AS (
          SELECT
            clue_id as c2b_clue_id,
            sale_clue_id as clue_id
          FROM guazi_dw_dwb.dwb_ctob_trade_order_day
          WHERE sale_clue_id > 0 
          AND dt = '${date_y_m_d}'
),
self_shelf AS (
     SELECT 
          a.clue_id -- 第二台车 
          ,c2b_clue_id
          ,ctob_busi_type_code
     FROM 
          (
               SELECT 
                    t1.clue_id 
                    ,t2.c2b_clue_id -- 第一台车ID
                    ,ctob_busi_type_code
               FROM 
               (
                    SELECT
                         clue_id, -- 第二台车 
                         ctob_busi_type_code
                    FROM   guazi_dw_dwd.dwd_ctob_car_owner_clue_transform_ymd  
                    WHERE dt = '${date_y_m_d}' 
                    AND ctob_busi_type_code IN (9,10)
               )t1
               LEFT JOIN changetable t2 ON t1.clue_id = t2.clue_id
          )a  
)
,tb_onshelf_time as 
(
        SELECT
            clue_id,
            SUBSTRING(onshelf_time, 1, 10) AS dt
            ,ctob_busi_type_code
        FROM guazi_dw_dwd.dim_ctob_auction_car_source_ymd
        WHERE dt = '${date_y_m_d}'
        AND ctob_busi_type_code IN (0,1,9,10) --- 所有C1新上架量
        union all -- C收车在C上架
	
        select 
            clue_id
           ,substring(create_time,1,10) dt 
            ,10 ctob_busi_type_code
        from guazi_dw_dw.dw_car_platform_quality_supply_detail_ymd
        where dt = '${date_y_m_d}'
        and create_time is not null 
        and clue_id in 
        (
        select clue_id from self_shelf where ctob_busi_type_code = 10
        ) 
),
clue_c2c AS (
  SELECT
    clue_id
    ,SUBSTRING(created_at, 1, 10) AS create_dt
  FROM guazi_dw_dwb.dwb_cars_car_source_tag_day
  WHERE dt = DATE_SUB(CURRENT_DATE, 1) 
  AND tag IN (1564,1580)
  group by 1,2
)


SELECT
    m.dt
    ,case when m.label='C自营' then 'C自营' 
          when m.label='B自营' then 'B自营'
          when m.shelf_type = 'C2C独售' then 'C2C独售' else 'C2B' end as shelf_type
    ,COUNT(DISTINCT m.clue_id) AS `新上架车源量`
    ,COUNT(DISTINCT n.clue_id) AS `回流车源量`
    ,COUNT(DISTINCT CASE WHEN n.dt = m.dt THEN n.clue_id END) AS `T0回流量`
    ,COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 1 DAY) THEN n.clue_id END) AS `T1累计回流量`
    ,COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 3 DAY) THEN n.clue_id END) AS `T3累计回流量`
    ,COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 5 DAY) THEN n.clue_id END) AS `T5累计回流量`
    ,COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 7 DAY) THEN n.clue_id END) AS `T7累计回流量`
    ,COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 14 DAY) THEN n.clue_id END) AS `T14累计回流量`
    ,COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 21 DAY) THEN n.clue_id END) AS `T21累计回流量`
    ,COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 35 DAY) THEN n.clue_id END) AS `T35累计回流量`
    ,COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 60 DAY) THEN n.clue_id END) AS `T60累计回流量`

FROM
(
        SELECT
            t1.dt
            ,t1.clue_id
            ,CASE WHEN t2.clue_id IS NOT NULL THEN 'C2C独售' ELSE '其他' END AS shelf_type
            ,CASE WHEN  t1.ctob_busi_type_code not in (9,10) THEN '非自营'  when t1.ctob_busi_type_code =9 then 'B自营' when t1.ctob_busi_type_code =10 then 'C自营' END AS label
        FROM
        (
            SELECT
                clue_id
                ,min(dt) dt 
                ,ctob_busi_type_code
            FROM tb_onshelf_time a  
            group by clue_id,
                    ctob_busi_type_code
        )t1
        LEFT JOIN clue_c2c t2 on t1.clue_id = t2.clue_id AND t1.dt= t2.create_dt
        LEFT JOIN self_shelf t3 ON t1.clue_id = t3.c2b_clue_id  --第一台车
        where t3.c2b_clue_id is  null    
        and  t1.dt BETWEEN '${start}' AND '${date_y_m_d}'
   
)m
LEFT JOIN
( -- 回流车源
    select
        clue_id
        ,substr(first_auction_time, 1, 10) dt -- 首次上拍时间
        ,is_once_reflow -- 是否回流过，1-是，0-否
    from guazi_dw_dw.dw_ctob_auction_car_source_statistic_ymd
    where dt = '${date_y_m_d}'
    and is_once_reflow = 1
)n ON m.clue_id = n.clue_id and m.dt <= n.dt
GROUP BY 1,2