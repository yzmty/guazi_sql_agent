/*
文件: 实体寄售加1000佣金数据源-cohort.sql
指标: 上架量|停售量|意向金量|有意向金的佣金commission|可售维度的佣金
业务: 实体寄售停售情况，意向金量，有意向金的佣金，和可售维度的佣金
场景: 实体寄售加佣金的实验复盘，主要统计加佣金后的停售、上架、意向金、佣金（意向金的佣金和可售的预估的佣金）等
标签: 实体寄售|上架|停售|意向金|佣金|燃油|新能源|C2C|cohort|可售佣金|可售
维度: 日期（上架日期）|gap_days（距上架天数）|fuel_type（能源类型）
核心表: dw_car_platform_quality_supply_detail_ymd|dwd_com_sale_orders_ymd|dwb_order_center_order_expense_day|dwd_com_consignment_clue_price_detail_ymd
作者: 文国庆|杨悦芳
描述: 实体寄售停售、上架、意向金、佣金（意向金的佣金和可售的预估的佣金）
*/
with supply as (
select dt,clue_id,tag_id,
CASE WHEN fuel_type IN (12, 13, 20) THEN '新能源' ELSE '燃油' END as fuel_type,
  CASE WHEN platform_price > 0 AND platform_price < 30000 THEN '(0，3w)' 
       WHEN platform_price >= 30000 AND platform_price < 50000 THEN '[3，5w)' 
       WHEN platform_price >= 50000 AND platform_price < 80000 THEN '[5，8w)' 
       WHEN platform_price >= 80000 AND platform_price < 120000 THEN '[8，12w)' 
       WHEN platform_price >= 120000 AND platform_price < 150000 THEN '[12，15w)'
       WHEN platform_price >= 150000 AND platform_price < 200000 THEN '[15，20w)' 
       ELSE '[20w，+)' END as  price_type
FROM
 guazi_dw_dw.dw_car_platform_quality_supply_detail_ymd
 WHERE dt BETWEEN '${start_time}' AND '${date_y_m_d}' 
 AND sku_type = 4 AND substr(cb_first_shelf_time,1,10)=dt
 and INSTR(CONCAT(',', valid_tags, ','), ',1554,') >= 1 -- 实体寄售
)  
,stop_sale as (
  select dt,clue_id,tag_id
  FROM guazi_dw_dw.dw_car_platform_quality_supply_detail_ymd
  WHERE dt BETWEEN '${start_time}' AND '${date_y_m_d}' 
 AND sku_type = 4 AND substr(stop_sale_time,1,10)=dt and car_source_status=3
 
)
-- 用订单表找佣金
, orders_bc_intent AS (
 select * from
 (SELECT
 substr(intention_money_finish_time, 1, 10) dt,
 clue_id,order_id,cancel_time,
 row_number () over (partition by substr(intention_money_finish_time, 1, 10),clue_id order by intention_money_finish_time desc ) rn
 FROM
 guazi_dw_dwd.dwd_com_sale_orders_ymd
 WHERE dt = '${date_y_m_d}' 
 AND substr(intention_money_finish_time, 1, 10) BETWEEN '${start_time}' AND '${date_y_m_d}'
  ) tt where rn=1
 )

, commission as ( -- C2C的佣金
   SELECT
      order_id,
        (sum(IF(expense_id IN ('10169', '200153', '200152', '200154'), amount, null)) / 100) commission
        FROM guazi_dw_dwb.dwb_order_center_order_expense_day 
    WHERE dt = '${date_y_m_d}' 
        AND expense_id IN ('10169', '200153', '200152', '200154')
        AND enabled = 1
        GROUP BY 1
        )
	
,orders_info as ( 
  select 
  a.dt,a.order_id,a.clue_id,a.cancel_time,b.commission
  from orders_bc_intent a 
  left join commission b on a.order_id =b.order_id
  
)
-- 直接找佣金
,yongjin as (
SELECT
    dt,
    clue_id,
    SUM(commission_price) AS commission_price
FROM
    guazi_dw_dwd.dwd_com_consignment_clue_price_detail_ymd
WHERE
    dt BETWEEN '2026-03-08' AND '${date_y_m_d}'
    AND commission_price IS NOT NULL
    AND commission_price > 0   
GROUP BY
    dt, clue_id
	)

,date_info as (

SELECT date_day
 FROM
 guazi_dw_dwd.dim_com_date_info_ymd
 WHERE date_day BETWEEN '${start_time}' AND '${date_y_m_d}'
  )

select 
t1.date_day dt,
t1.gap_days,
t2.fuel_type,

count(distinct t2.clue_id) as `上架量`,
count(distinct t4.clue_id) as `停售量`,
count(distinct t3.clue_id) as `意向金量`,
sum(commission)  commission ,-- 车均佣金 = commission / 意向金量
sum(yj.commission_price) as `佣金`,   -- 这里是可售维度，后续用commission/上架量=车均 


-- 意向金未退口径
-- count(distinct case when t3.cancel_time is null then t3.clue_id end) as `意向金未退量`
-- sum(case when t3.cancel_time is null then commission_price end) as `意向金未退佣金`
from 
 (SELECT
 stat_day.date_day,
 gap_days.date_day date_end_day,
 TIMESTAMPDIFF(DAY, CAST(stat_day.date_day AS DATE), CAST(gap_days.date_day AS DATE)) AS gap_days
 FROM
 date_info stat_day
 LEFT JOIN date_info gap_days ON stat_day.date_day <= gap_days.date_day
 ) t1 
 left join supply t2 on t1.date_day=t2.dt 
left join orders_info t3 on t2.clue_id=t3.clue_id and t1.date_end_day=t3.dt 
left join yongjin yj on t2.clue_id=yj.clue_id and t1.date_end_day=yj.dt 
 left join stop_sale t4 on t2.clue_id=t4.clue_id and t1.date_end_day=t4.dt
 where t1.gap_days <= 30
 group by 1,2,3
 order by 1,2 ,3