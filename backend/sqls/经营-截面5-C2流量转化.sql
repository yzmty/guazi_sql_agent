/*
文件: 经营-截面5-C2流量转化.sql
指标: 大盘列表页曝光pv|虚拟寄售列表页曝光pv|门店寄售列表页曝光pv|虚拟寄售车源量|门店寄售车源量|虚拟寄售净已定量|门店寄售净已定量
业务: C2流量转化分析
场景: 统计虚拟寄售和门店寄售两种模式的列表页曝光PV、车源量、净已定量，用于分析不同寄售模式的曝光效果和转化情况
标签: 截面|寄售|曝光|列表页|PV|车源量|净已定量|虚拟寄售|门店寄售|C2|经营周报|转化|C2C
维度: dt|clue_type
核心表: ads_category_operation_stat_inc_ymd
作者: 文国庆
描述: 主要是C2C的虚拟寄售和门店寄售的分析，获取C2流量转化指标，包括大盘列表页曝光pv、虚拟寄售列表页曝光pv、门店寄售列表页曝光pv、虚拟寄售车源量、门店寄售车源量、虚拟寄售净已定量、门店寄售净已定量
*/
with exposure as (
  select
    dt,
    case
      when is_cb_sale = 1 and is_consignment_car = 3 then '门店寄售'
	  when is_cb_sale = 1 and is_consignment_car != 3 then '虚拟寄售'
      else '其他'
    end as clue_type,
    sum(coalesce(list_pv, 0)) + sum(coalesce(zone_list_feed_beseen_pv, 0)) + sum(coalesce(fuel_list_feed_beseen_pv, 0)) + sum(coalesce(newenergy_feed_feed_list_beseen_pv, 0)) + sum(
      coalesce(old_newenergy_feed_feed_list_beseen_pv, 0)
    ) as list_pv,
    sum(coalesce(detail_pv, 0)) as detail_pv,
    sum(coalesce(list_clue_cnt, 0)) as list_clue_cnt,
    sum(coalesce(core_assignment_record_cnt, 0)) as assignment_cnt,
    sum(coalesce(intention_money_finish_cnt, 0)) as pay_cnt,
    sum(coalesce(intention_money_finish_cnt, 0)) - coalesce(sum(cancel_intention_money_finish_cnt), 0) as net_pay_cnt,
    sum(coalesce(cansale_cnt, 0)) as cansale_cnt,
    sum(coalesce(user_confirm_transfer_cnt, 0)) as user_confirm_transfer_cnt,
    sum(coalesce(deliver_car_prepay_cnt, 0)) as deliver_car_prepay_cnt,
	(sum(intention_money_finish_cnt) - sum(cancel_intention_money_finish_cnt)) as net_prepay_cnt -- 净已定量
  from
    guazi_dw_ads.ads_category_operation_stat_inc_ymd
  where
    dt between '${start_date}' and '${date_y_m_d}'
  group by
    1,
    2
)
SELECT
  dt,
  sum(list_pv) as `大盘列表页曝光pv`,
  sum(if(clue_type = '虚拟寄售', list_pv, null)) as `虚拟寄售列表页曝光pv`,
  sum(if(clue_type = '门店寄售', list_pv, null)) as `门店寄售列表页曝光pv`,
  sum(if(clue_type = '虚拟寄售', list_clue_cnt, null)) as `虚拟寄售车源量`,
  sum(if(clue_type = '门店寄售', list_clue_cnt, null)) as `门店寄售车源量`,
  sum(if(clue_type = '虚拟寄售', net_prepay_cnt, null)) as `虚拟寄售净已定量`,
  sum(if(clue_type = '门店寄售', net_prepay_cnt, null)) as `门店寄售净已定量`
from
  exposure
group by 1
order by 1