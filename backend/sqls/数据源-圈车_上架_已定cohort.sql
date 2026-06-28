/*
文件: 数据源-圈车_上架_已定cohort.sql
指标: 新上架车源量|T0已定量|T1累计已定量|T3累计已定量|T5累计已定量|T7累计已定量|T14累计已定量|T21累计已定量|T30累计已定量|T60累计已定量|T0真实收入|T1真实收入|T3真实收入|T5真实收入|T7真实收入|T14真实收入|T21真实收入|T30真实收入|T60真实收入
业务: C1圈车首上架渠道Cohort转化分析
场景: 按首上架日期统计C1车源在不同时间窗口的累计已定量和收入，含圈车类型、首上架渠道、BC同售标识、售出渠道、价格带、能源类型等维度
标签: 圈车|首上架|cohort|转化|已定量|营收|收入|C1|BC同售|价格带|燃油|新能源|燃油类型|渠道
维度: dt（首上架日期）|新类型（圈车类型-首上架渠道归类）|圈车类型|首上架渠道|首上架渠道-是否BC同售|售出渠道|selling_channel|deal_price（价格带）|deal_price_wide（宽价格带）|fuel_type（能源类型）
核心表: dw_ctob_c1_car_source_ymd|dw_ctob_c1_tob_toc_appoint_detail_ymd|dwd_ctob_car_owner_order_record_ymd|dwb_guazi_client_seller_car_owner_order_record_day
作者: 文国庆|杨悦芳
描述: 按圈车类型和首上架渠道统计C1车源上架后的T0~T60天已定量和收入
*/
with a as (
SELECT
    m.dt
	,m.`圈车类型`
    ,m.`首上架渠道`
	,m.`首上架渠道-是否BC同售`
	,case 
            when n.selling_channel in ('C2C','C_purchase_C_sale') then 'C售出' 
            when n.selling_channel in ('C2B','B_purchase_B_sale','C_purchase_B_sale') then 'B售出' 
            else n.selling_channel 
        end as `售出渠道`
	,n.selling_channel
	,n.deal_price
	,n.deal_price_wide
	,fuel_type
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
(SELECT distinct 
    substr(onshelf_time, 1, 10) AS dt,
    CASE WHEN car_collect_platform = 2 OR consign_choose_type IN (1, 2) THEN 'C圈车' ELSE 'B圈车' END AS `圈车类型`,
    CASE
		WHEN first_onshelf_biz_line = 'C2C独售-虚拟' THEN '首上虚拟寄售'
		WHEN first_onshelf_biz_line =  'C2C独售-门店' THEN'首上实体寄售'
        WHEN first_onshelf_biz_line =  'C2B' THEN '首上C2B'
        WHEN first_onshelf_biz_line =  '自营C' THEN '首上自营C'
        WHEN first_onshelf_biz_line =  '自营B' THEN '首上自营B'
        ELSE first_onshelf_biz_line
    END AS `首上架渠道`,
	CASE WHEN t2.clue_id IS NOT NULL THEN 'BC同售' else '非BC同售' end `首上架渠道-是否BC同售`,
	case when fuel_type in (12,13,20) then '新能源' else '燃油车' end as fuel_type ,
    COALESCE(t1.clue_id_self,t1.clue_id) clue_id
FROM guazi_dw_dw.dw_ctob_c1_car_source_ymd t1
LEFT JOIN (
    -- C2C转BC同售车源（当日售卖概率低转同售）
    SELECT DISTINCT a.clue_id
    FROM guazi_dw_dwd.dwd_ctob_car_owner_order_record_ymd a
    INNER JOIN guazi_dw_dwb.dwb_guazi_client_seller_car_owner_order_record_day b
        ON a.order_id = b.order_id
        AND a.dt = b.dt
        AND a.change_reason = b.change_reason
    WHERE a.dt = '${date_y_m_d}'
      AND a.change_reason = 14
      AND b.ext LIKE '%system_v2_new_listing%'
) t2 ON COALESCE(t1.clue_id_self, t1.clue_id) = t2.clue_id
	WHERE t1.dt = '${date_y_m_d}'
  AND t1.is_c1_clue = 1 -- C1车源
  and substr(onshelf_time,1,10) between '${start}' AND '${date_y_m_d}'
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
		,case
                when deal_price is null or deal_price = 0 then '无成交价'  -- C1车主到手价（对于自营是收车价、对于C端售卖来讲是车主到手价、对于B端售卖成交价）
                when deal_price <= 10000 then 'a.(0-1]'
                when deal_price <= 20000 then 'b.(1-2]'
                when deal_price <= 40000 then 'c.(2-4]'
                when deal_price <= 65000 then 'd.(4-6.5]'
                when deal_price <= 100000 then 'e.(6.5-10]'
                when deal_price <= 150000 then 'f.(10-15]'
                when deal_price <= 200000 then 'g.(15-20]'
                when deal_price <= 300000 then 'h.(20-30]'
                when deal_price <= 500000 then 'i.(30-50]'
                when deal_price > 500000 then 'j.(50+)'
                else '无成交价'
            end as deal_price	
			-- 宽价格段
			,case
				when deal_price is null or deal_price = 0 then '无成交价'
				when deal_price <= 65000  then '(0-6.5]'
				when deal_price <= 100000 then '(6.5-10]'
				when deal_price <= 150000 then '(10-15]'
				when deal_price <= 200000 then '(15-20]'
				else '(20+)'
			end as deal_price_wide
			,sum(prepay_before_discount_sales_service_fee) service_fee
			,sum(prepay_sales_service_fee) actual_service_fee
			,sum(acquisition_spread_income) purchase_income
    from guazi_dw_dw.dw_ctob_c1_tob_toc_appoint_detail_ymd
    where dt ='${date_y_m_d}'
	  and ctob_busi_type_code in(1,9,10)
    and ctob_deal_busi_code not in (4,7,9) -- 剔除第一台车
    and substr(prepay_time,1,10) between '${start}' AND '${date_y_m_d}'
	group by 1,2,3,4,5
)n ON m.clue_id = n.clue_id and m.dt <= n.dt
GROUP BY 1,2,3,4,5,6,7,8,9
)

select 
    dt AS `日期`
	,CONCAT(`圈车类型`, "-", 
        CASE 
            WHEN `首上架渠道` IN ('首上虚拟寄售', '首上实体寄售') THEN '首上C2C'
            ELSE `首上架渠道`
        END
    ) AS `新类型`
	,`圈车类型`
   ,`首上架渠道`
   ,`首上架渠道-是否BC同售`
   ,`售出渠道`
   ,deal_price
	,deal_price_wide
	,fuel_type
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
group by 1,2,3,4,5,6,7,8,9
order by 1,2,3,4,5,6,7,8,9