/*
文件: 首上架数据源1-C1首上架转化情况.sql
指标: 新上架车源量|T0已定量|T1累计已定量|T3累计已定量|T5累计已定量|T7累计已定量|T14累计已定量|T21累计已定量|T30累计已定量|T60累计已定量|T0应收佣金|T1应收佣金|T3应收佣金|T5应收佣金|T7应收佣金|T14应收佣金|T21应收佣金|T30应收佣金|T60应收佣金|T0实收佣金|T1实收佣金|T3实收佣金|T5实收佣金|T7实收佣金|T14实收佣金|T21实收佣金|T30实收佣金|T60实收佣金|T0价差收入|T1价差收入|T3价差收入|T5价差收入|T7价差收入|T14价差收入|T21价差收入|T30价差收入|T60价差收入|T0真实收入|T1真实收入|T3真实收入|T5真实收入|T7真实收入|T14真实收入|T21真实收入|T30真实收入|T60真实收入
业务: C1首上架渠道转化cohort分析
场景: 按首上架日期（cohort）统计C1车源在不同时间窗口的累计已定量和收入，用于分析不同首上架渠道的转化效率
标签: 首上架|cohort|转化|已定量|佣金|价差|真实收入|C1
维度: dt（首上架日期）|渠道大类（C2C/自营C/自营B/C2B）|首上架渠道|售出渠道
核心表: dw_ctob_c1_car_source_ymd|dw_ctob_c1_tob_toc_appoint_detail_ymd
作者: 未知|杨悦芳
描述: 按首上架渠道统计C1车源上架后的T0~T60天已定量和收入
*/
with a as (
SELECT
    m.dt
    ,case when m.first_onshelf_biz_line in ('C2C独售-虚拟','C2C独售-门店') then 'C2C' else m.first_onshelf_biz_line end as line
    ,m.first_onshelf_biz_line 
    ,n.selling_channel
    ,IFNULL(COUNT(DISTINCT m.clue_id),0) AS up_num
    ,IFNULL(COUNT(DISTINCT CASE WHEN n.dt = m.dt THEN n.clue_id END),0) AS t0_deal
    ,IFNULL(COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 1 DAY) THEN n.clue_id END),0) AS t1_deal
    ,IFNULL(COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 3 DAY) THEN n.clue_id END),0) AS t3_deal
    ,IFNULL(COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 5 DAY) THEN n.clue_id END),0) AS t5_deal
    ,IFNULL(COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 7 DAY) THEN n.clue_id END),0) AS t7_deal
    ,IFNULL(COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 14 DAY) THEN n.clue_id END),0) AS t14_deal
    ,IFNULL(COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 21 DAY) THEN n.clue_id END),0) AS t21_deal
    ,IFNULL(COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 30 DAY) THEN n.clue_id END),0) AS t30_deal
    ,IFNULL(COUNT(DISTINCT CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 60 DAY) THEN n.clue_id END),0) AS t60_deal
    ,IFNULL(sum(CASE WHEN n.dt = m.dt THEN n.service_fee END),0) AS t0_fee
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 1 DAY) THEN n.service_fee END),0) AS t1_fee
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 3 DAY) THEN n.service_fee END),0) AS t3_fee
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 5 DAY) THEN n.service_fee END),0) AS t5_fee
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 7 DAY) THEN n.service_fee END),0) AS t7_fee
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 14 DAY) THEN n.service_fee END),0) AS t14_fee
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 21 DAY) THEN n.service_fee END),0) AS t21_fee
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 30 DAY) THEN n.service_fee END),0) AS t30_fee
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 60 DAY) THEN n.service_fee END),0) AS t60_fee
    ,IFNULL(sum(CASE WHEN n.dt = m.dt THEN n.actual_service_fee END),0) AS t0_actual
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 1 DAY) THEN n.actual_service_fee END),0) AS t1_actual
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 3 DAY) THEN n.actual_service_fee END),0) AS t3_actual
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 5 DAY) THEN n.actual_service_fee END),0) AS t5_actual
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 7 DAY) THEN n.actual_service_fee END),0) AS t7_actual
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 14 DAY) THEN n.actual_service_fee END),0) AS t14_actual
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 21 DAY) THEN n.actual_service_fee END),0) AS t21_actual
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 30 DAY) THEN n.actual_service_fee END),0) AS t30_actual
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 60 DAY) THEN n.actual_service_fee END),0) AS t60_actual
    ,IFNULL(sum(CASE WHEN n.dt = m.dt THEN n.purchase_income END),0) AS t0_diff
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 1 DAY) THEN n.purchase_income END),0) AS t1_diff
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 3 DAY) THEN n.purchase_income END),0) AS t3_diff
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 5 DAY) THEN n.purchase_income END),0) AS t5_diff
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 7 DAY) THEN n.purchase_income END),0) AS t7_diff
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 14 DAY) THEN n.purchase_income END),0) AS t14_diff
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 21 DAY) THEN n.purchase_income END),0) AS t21_diff
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 30 DAY) THEN n.purchase_income END),0) AS t30_diff
    ,IFNULL(sum(CASE WHEN n.dt <= DATE_ADD(m.dt, INTERVAL 60 DAY) THEN n.purchase_income END),0) AS t60_diff
FROM
( 
     select 
          substr(onshelf_time,1,10) dt
         ,first_onshelf_biz_line
         ,case when clue_id_self is not null then clue_id_self else clue_id end as clue_id
     from guazi_dw_dw.dw_ctob_c1_car_source_ymd t1
     where dt ='${date_y_m_d}'
     and is_c1_clue = 1
     and substr(onshelf_time,1,10) between '${start}' and '${date_y_m_d}'  
     group by 1,2,3 
)m
LEFT JOIN
(
	    select 
        substr(prepay_time,1,10) dt
        ,clue_id
      		 ,CASE WHEN ctob_busi_type_code = 9 AND ctob_deal_busi_code not in(-1,3) THEN 'B_purchase_B_sale'        
               WHEN ctob_busi_type_code IN (0,1) AND ctob_deal_busi_code not in(-1,3) THEN 'C2B' 
               WHEN ctob_busi_type_code = 10 AND ctob_deal_busi_code not in(-1,3) THEN 'C_purchase_B_sale'         
               WHEN ctob_busi_type_code = 10 AND ctob_deal_busi_code in (-1,3) THEN 'C_purchase_C_sale'
               WHEN ctob_busi_type_code IN (0,1) and ctob_deal_busi_code in (-1,3) THEN 'C2C' 
               ELSE concat(ctob_busi_type_code,'',ctob_deal_busi_code) END AS selling_channel
			,sum(prepay_before_discount_sales_service_fee) service_fee
			,sum(prepay_sales_service_fee) actual_service_fee
			,sum(acquisition_spread_income) purchase_income
    from guazi_dw_dw.dw_ctob_c1_tob_toc_appoint_detail_ymd
    where dt ='${date_y_m_d}'
	  and ctob_busi_type_code in(1,9,10)
    and ctob_deal_busi_code not in (4,7,9) -- 剔除第一台车
    and substr(prepay_time,1,10) between '${start}' AND '${date_y_m_d}'
	group by 1,2,3
)n ON m.clue_id = n.clue_id and m.dt <= n.dt
GROUP BY 1,2,3,4
)
select 
    dt AS `日期`
   ,line AS `渠道大类`
   ,first_onshelf_biz_line AS `首上架渠道`
   ,selling_channel AS `售出渠道`
   ,sum(up_num) AS `新上架车源量`
   ,sum(t0_deal) AS `T0已定量`
   ,sum(t1_deal) AS `T1累计已定量`
   ,sum(t3_deal) AS `T3累计已定量`
   ,sum(t5_deal) AS `T5累计已定量`
   ,sum(t7_deal) AS `T7累计已定量`
   ,sum(t14_deal) AS `T14累计已定量`
   ,sum(t21_deal) AS `T21累计已定量`
   ,sum(t30_deal) AS `T30累计已定量`
   ,sum(t60_deal) AS `T60累计已定量`
   ,sum(t0_fee) AS `T0应收佣金`
   ,sum(t1_fee) AS `T1应收佣金`
   ,sum(t3_fee) AS `T3应收佣金`
   ,sum(t5_fee) AS `T5应收佣金`
   ,sum(t7_fee) AS `T7应收佣金`
   ,sum(t14_fee) AS `T14应收佣金`
   ,sum(t21_fee) AS `T21应收佣金`
   ,sum(t30_fee) AS `T30应收佣金`
   ,sum(t60_fee) AS `T60应收佣金`
   ,sum(t0_actual) AS `T0实收佣金`
   ,sum(t1_actual) AS `T1实收佣金`
   ,sum(t3_actual) AS `T3实收佣金`
   ,sum(t5_actual) AS `T5实收佣金`
   ,sum(t7_actual) AS `T7实收佣金`
   ,sum(t14_actual) AS `T14实收佣金`
   ,sum(t21_actual) AS `T21实收佣金`
   ,sum(t30_actual) AS `T30实收佣金`
   ,sum(t60_actual) AS `T60实收佣金`
   ,sum(t0_diff) AS `T0价差收入`
   ,sum(t1_diff) AS `T1价差收入`
   ,sum(t3_diff) AS `T3价差收入`
   ,sum(t5_diff) AS `T5价差收入`
   ,sum(t7_diff) AS `T7价差收入`
   ,sum(t14_diff) AS `T14价差收入`
   ,sum(t21_diff) AS `T21价差收入`
   ,sum(t30_diff) AS `T30价差收入`
   ,sum(t60_diff) AS `T60价差收入`
   ,sum(case when selling_channel="C2C" then t0_fee
     when selling_channel="C2B" then t0_actual
     when selling_channel="B_purchase_B_sale" then t0_actual+t0_diff 
     when selling_channel="C_purchase_C_sale" then t0_diff 
     when selling_channel="C_purchase_B_sale" then t0_actual+t0_diff  else 0 end) as `T0真实收入`
   ,sum(case when selling_channel="C2C" then t1_fee
     when selling_channel="C2B" then t1_actual
     when selling_channel="B_purchase_B_sale" then t1_actual+t1_diff 
     when selling_channel="C_purchase_C_sale" then t1_diff 
     when selling_channel="C_purchase_B_sale" then t1_actual+t1_diff  else 0 end) as `T1真实收入`
   ,sum(case when selling_channel="C2C" then t3_fee
     when selling_channel="C2B" then t3_actual
     when selling_channel="B_purchase_B_sale" then t3_actual+t3_diff 
     when selling_channel="C_purchase_C_sale" then t3_diff 
     when selling_channel="C_purchase_B_sale" then t3_actual+t3_diff  else 0 end) as `T3真实收入`
   ,sum(case when selling_channel="C2C" then t5_fee
     when selling_channel="C2B" then t5_actual
     when selling_channel="B_purchase_B_sale" then t5_actual+t5_diff 
     when selling_channel="C_purchase_C_sale" then t5_diff 
     when selling_channel="C_purchase_B_sale" then t5_actual+t5_diff  else 0 end) as `T5真实收入`
   ,sum(case when selling_channel="C2C" then t7_fee
     when selling_channel="C2B" then t7_actual
     when selling_channel="B_purchase_B_sale" then t7_actual+t7_diff 
     when selling_channel="C_purchase_C_sale" then t7_diff 
     when selling_channel="C_purchase_B_sale" then t7_actual+t7_diff  else 0 end) as `T7真实收入`
   ,sum(case when selling_channel="C2C" then t14_fee
     when selling_channel="C2B" then t14_actual
     when selling_channel="B_purchase_B_sale" then t14_actual+t14_diff 
     when selling_channel="C_purchase_C_sale" then t14_diff 
     when selling_channel="C_purchase_B_sale" then t14_actual+t14_diff  else 0 end) as `T14真实收入`
   ,sum(case when selling_channel="C2C" then t21_fee
     when selling_channel="C2B" then t21_actual
     when selling_channel="B_purchase_B_sale" then t21_actual+t21_diff 
     when selling_channel="C_purchase_C_sale" then t21_diff 
     when selling_channel="C_purchase_B_sale" then t21_actual+t21_diff  else 0 end) as `T21真实收入`
   ,sum(case when selling_channel="C2C" then t30_fee
     when selling_channel="C2B" then t30_actual
     when selling_channel="B_purchase_B_sale" then t30_actual+t30_diff 
     when selling_channel="C_purchase_C_sale" then t30_diff 
     when selling_channel="C_purchase_B_sale" then t30_actual+t30_diff  else 0 end) as `T30真实收入`
   ,sum(case when selling_channel="C2C" then t60_fee
     when selling_channel="C2B" then t60_actual
     when selling_channel="B_purchase_B_sale" then t60_actual+t60_diff 
     when selling_channel="C_purchase_C_sale" then t60_diff 
     when selling_channel="C_purchase_B_sale" then t60_actual+t60_diff  else 0 end) as `T60真实收入`
from a
group by 1,2,3,4
order by 1,2,3,4