/*
文件: 数据源-圈车_净已定.sql
指标: quantity_set（净已定量）|actual_service_fee（实收佣金）|purchase_income（价差收入）|总收入
业务: C1首上架渠道已定量及收入汇总
场景: C1车源的净已定量及各类收入，用于分析不同维度的收入贡献
标签: 首上架|已定量|价差|收入|C1|圈车|价格带|燃油|新能源|净已定|截面|营收
维度: prepay_time（已定日期）|圈车类型|首上架渠道|首上架渠道-是否BC同售|售出渠道|selling_channel|fuel_type（能源类型）|deal_price（价格带）|deal_price_wide（宽价格带）
核心表: dw_ctob_c1_tob_toc_appoint_detail_ymd|dw_ctob_c1_car_source_ymd|dwd_ctob_car_owner_order_record_ymd|dwb_guazi_client_seller_car_owner_order_record_day
作者: 文国庆|杨悦芳
描述: 按首上架渠道汇总净已定量、实收佣金、价差收入、总收入，含圈车类型、能源类型、价格带维度
*/
-- Save New Duplicate & Edit Just Text Twitter
-- 用于C1最新周报，用的是C1链路新表，和截面数据源1-净已定(2026.5.12)的区别是，这个是我改造过的增加了燃油类型，价格带，宽价格带
-- 截面数据源1:净已定量&营收
select 
    prepay_time as dt,
	`圈车类型`,
	`首上架渠道`,
	-- `首上架渠道-是否BC同售`,
	case 
            when selling_channel in ('C2C','C_purchase_C_sale','实体寄售','虚拟寄售') then 'C售出' 
            when selling_channel in ('C2B','B_purchase_B_sale','C_purchase_B_sale') then 'B售出' 
            else selling_channel 
        end as `售出渠道` ,
    selling_channel,
	
	fuel_type, -- 燃油类型
	deal_price,
	deal_price_wide,
    quantity_set,
    -- service_fee, -- 应收佣金
    actual_service_fee, -- 实收佣金
    purchase_income, -- 价差收入
    `总收入`
from
(select 
    t1.prepay_time
	,fuel_type  -- 燃油类型
	,deal_price
	,deal_price_wide 
	,`圈车类型`
    ,selling_channel
    ,CASE
		WHEN first_onshelf_biz_line = 'C2C独售-虚拟' THEN '首上虚拟寄售'
		WHEN first_onshelf_biz_line =  'C2C独售-门店' THEN'首上实体寄售'
        WHEN first_onshelf_biz_line =  'C2B' THEN '首上C2B'
        WHEN first_onshelf_biz_line =  '自营C' THEN '首上自营C'
        WHEN first_onshelf_biz_line =  '自营B' THEN '首上自营B'
        ELSE first_onshelf_biz_line
    END AS `首上架渠道`
	,CASE WHEN t3.clue_id IS NOT NULL THEN 'BC同售' else '非BC同售' end `首上架渠道-是否BC同售`
    ,IFNULL(sum(quantity_set),0)as quantity_set
	 ,IFNULL(sum(prepay_before_discount_sales_service_fee),0) as service_fee
	 ,IFNULL(sum(prepay_sales_service_fee),0) as actual_service_fee
	 ,IFNULL(sum(acquisition_spread_income),0) as purchase_income
	 ,IFNULL(sum(case when selling_channel = 'C2C' then prepay_before_discount_sales_service_fee else prepay_sales_service_fee end),0)+IFNULL(sum(acquisition_spread_income),0) as `总收入`
   
from 
(
	 select -- 已定
        substr(prepay_time,1,10) prepay_time
        ,clue_id
		,case when ctob_busi_type_code in (1) and ctob_deal_busi_code not in (-1,3,8) then 'C2B'
		when ctob_busi_type_code in (9) and ctob_deal_busi_code not in (-1,3) then '自营Btob'
		when ctob_busi_type_code in (1) and ctob_deal_busi_code in (-1,3) and is_consign_resell = 1 then '实体寄售'
		when ctob_busi_type_code in (1) and ctob_deal_busi_code in(-1,3) and is_consign_resell !=1 then '虚拟寄售'
		when ctob_busi_type_code in (10) and ctob_deal_busi_code in (-1,3) then '自营Ctoc'
		when ctob_busi_type_code in (10) and ctob_deal_busi_code not in (-1, 3) then '自营Ctob'
		else concat(ctob_busi_type_code,'_',ctob_deal_busi_code)end as selling_channel
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
			
			,1 as quantity_set
			,sum(prepay_before_discount_sales_service_fee) prepay_before_discount_sales_service_fee
			,sum(prepay_sales_service_fee) prepay_sales_service_fee
			,sum(acquisition_spread_income) acquisition_spread_income
    from guazi_dw_dw.dw_ctob_c1_tob_toc_appoint_detail_ymd
    where dt ='${date_y_m_d}'
	  and ctob_busi_type_code in(1,9,10)
    and ctob_deal_busi_code not in (4,7,9) -- 剔除第一台车
    and substr(prepay_time,1,10) between '${start}' AND '${date_y_m_d}'
	  group by 1,2,3,4 ,5
	
	union ALL
	
	 select -- 已定后退
        substr(refund_time,1,10) refund_time
        ,clue_id
		
		,case when ctob_busi_type_code in (1) and ctob_deal_busi_code not in (-1,3,8) then 'C2B'
		when ctob_busi_type_code in (9) and ctob_deal_busi_code not in (-1,3) then '自营Btob'
		when ctob_busi_type_code in (1) and ctob_deal_busi_code in (-1,3) and is_consign_resell = 1 then '实体寄售'
		when ctob_busi_type_code in (1) and ctob_deal_busi_code in(-1,3) and is_consign_resell !=1 then '虚拟寄售'
		when ctob_busi_type_code in (10) and ctob_deal_busi_code in (-1,3) then '自营Ctoc'
		when ctob_busi_type_code in (10) and ctob_deal_busi_code not in (-1, 3) then '自营Ctob'
		else concat(ctob_busi_type_code,'_',ctob_deal_busi_code)end as selling_channel
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
			
			,-1 as quantity_set
			,sum(prepay_before_discount_sales_service_fee)*-1.000 prepay_before_discount_sales_service_fee
			,sum(prepay_sales_service_fee)*-1.000 prepay_sales_service_fee
			,sum(acquisition_spread_income)*-1.000 acquisition_spread_income
    from guazi_dw_dw.dw_ctob_c1_tob_toc_appoint_detail_ymd
    where dt ='${date_y_m_d}'
	  and ctob_busi_type_code in(1,9,10)
    and ctob_deal_busi_code not in (4,7,9) -- 剔除第一台车
    and substr(refund_time,1,10) between '${start}' AND '${date_y_m_d}'
	  group by 1,2,3,4	,5
)t1
left join 
(
    select 
          substr(onshelf_time,1,10) dt
          ,first_onshelf_biz_line
		  ,CASE WHEN car_collect_platform = 2 OR consign_choose_type IN (1, 2) THEN 'C圈车' ELSE 'B圈车' END AS `圈车类型`
		  ,case when fuel_type in (12,13,20) then '新能源' else '燃油车' end as fuel_type 
          ,case when clue_id_self is not null then clue_id_self else clue_id end as clue_id
     from guazi_dw_dw.dw_ctob_c1_car_source_ymd t1
     where dt ='${date_y_m_d}'
     and is_c1_clue = 1 -- C1车源
     and substr(onshelf_time,1,10) is not null -- 已经上架
     group by 1,2,3 ,4,5
)t2 on t1.clue_id = t2.clue_id
left join 
(
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
)t3 on t2.clue_id = t3.clue_id
group by 1,2,3,4,5,6,7,8
 ) t