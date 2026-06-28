/*
文件: 截面数据源1-净已定(新数据源).sql
指标: 净已定quantity_set|应收佣金service_fee|实收佣金actual_service_fee|价差收入purchase_income|总收入
业务: C1净已定车
场景: 分析C1成交车源的净已定数量和营收构成(应收佣金、实收佣金、价差收入)
标签: 成交|营收|佣金|价差|净已定|自营|C2C|C2B|C1
维度: 截面|渠道|dt|首上架渠道|售卖渠道selling_channel|燃油类型fuel_type|价格带deal_price|宽价格带deal_price_wide
核心表: dw_ctob_c1_tob_toc_appoint_detail_ymd|dw_ctob_c1_car_source_ymd
作者: 未知
描述: 基于C1链路新表计算净已定量及营收构成，包括应收佣金、实收佣金、价差收入和总收入，按渠道、燃油类型、价格段等维度汇总
*/
-- Save New Duplicate & Edit Just Text Twitter
-- 用于C1最新周报，用的是C1链路新表，和截面数据源1-净已定(2026.5.12)的区别是，这个是我改造过的增加了燃油类型，价格带，宽价格带
-- - 截面数据源1:净已定量&营收
select 
    case 
            when selling_channel in ('C_purchase_C_sale','C_purchase_B_sale') then 'C端自营' 
            when selling_channel = 'B_purchase_B_sale' then 'B端自营' 
            else selling_channel 
        end as `渠道`,
    prepay_time as dt,
	`首上架渠道`,
    selling_channel,
	fuel_type, -- 燃油类型
	deal_price,
	deal_price_wide,
    quantity_set,
    service_fee, -- 应收佣金
    actual_service_fee, -- 实收佣金
    purchase_income, -- 价差收入
    `总收入`
from
(select 
    t1.prepay_time
	,fuel_type  -- 燃油类型
	,deal_price
	,deal_price_wide 
    ,selling_channel
    ,case when first_onshelf_biz_line in ('C2C独售-虚拟','C2C独售-门店') then 'C2C' else first_onshelf_biz_line end as  `首上架渠道`
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
          when ctob_busi_type_code in (9) and ctob_deal_busi_code not in (-1,3) then 'B_purchase_B_sale' 
          when ctob_busi_type_code in (1) and ctob_deal_busi_code  in (-1,3) then 'C2C' 
          when ctob_busi_type_code in (10) and ctob_deal_busi_code in (-1,3) then 'C_purchase_C_sale'
          when ctob_busi_type_code in (10) and ctob_deal_busi_code not in (-1,3) then 'C_purchase_B_sale'  
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
				when deal_price <= 40000  then '(0-4]'
				when deal_price <= 100000 then '(4-10]'
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
          when ctob_busi_type_code in (9) and ctob_deal_busi_code not in (-1,3) then 'B_purchase_B_sale' 
          when ctob_busi_type_code in (1) and ctob_deal_busi_code  in (-1,3) then 'C2C' 
          when ctob_busi_type_code in (10) and ctob_deal_busi_code in (-1,3) then 'C_purchase_C_sale'
          when ctob_busi_type_code in (10) and ctob_deal_busi_code not in (-1,3) then 'C_purchase_B_sale'  
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
				when deal_price <= 40000  then '(0-4]'
				when deal_price <= 100000 then '(4-10]'
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
		  
		  ,case when fuel_type in (12,13,20) then '新能源' else '燃油车' end as fuel_type 
          ,case when clue_id_self is not null then clue_id_self else clue_id end as clue_id
     from guazi_dw_dw.dw_ctob_c1_car_source_ymd t1
     where dt ='${date_y_m_d}'
     and is_c1_clue = 1 -- C1车源
     and substr(onshelf_time,1,10) is not null -- 已经上架
     group by 1,2,3 ,4
)t2 on t1.clue_id = t2.clue_id
group by 1,2,3,4,5,6
 ) t