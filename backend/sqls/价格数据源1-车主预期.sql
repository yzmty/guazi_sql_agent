/*
文件: 价格数据源1-车主预期.sql
指标: 上架量|有原始底价的上架量|车主原始心理底价覆盖率|车主原始心理底价|上架时车主到手模型价|车主预期偏离度
业务: C1的C2B
场景: 分析C2C可售车源的车主预期的覆盖率和车主预期的偏离度
标签：车主预期|C2B|上架量|有原始底价的上架量|车主原始心理底价覆盖率|车主原始心理底价|上架时车主到手模型价|车主预期偏离度
维度: 上架日期dt|价格段model_price_region|燃油类型fuel_type
核心表: dim_ctob_auction_car_source_ymd
作者: 文国庆|杨悦芳
描述: 分析C2B拍场的车主预期的覆盖率和车主预期的偏离度|（1）车主原始心理底价覆盖率 = 填写了车主原始心理底价的上架量 / 总上架量|（2）车主预期偏离度 = 车主原始心理底价 / 上架时车主到手价模型价
*/
-- 车主预期：
-- ①车主原始心理底价覆盖率 = 填写了车主原始心理底价的上架量 / 总上架量
-- ②车主预期偏离度 = 车主原始心理底价 / 上架时车主到手价模型价
select
    substring(onshelf_time, 1, 10) as dt, -- 上架时间
    case
        when (seller_model_price * 1.0 / 10000) > 0   and (seller_model_price * 1.0 / 10000) <= 3   then '(0-3]'
        when (seller_model_price * 1.0 / 10000) > 3   and (seller_model_price * 1.0 / 10000) <= 5   then '(3-5]'
        when (seller_model_price * 1.0 / 10000) > 5   and (seller_model_price * 1.0 / 10000) <= 8   then '(5-8]'
        when (seller_model_price * 1.0 / 10000) > 8   and (seller_model_price * 1.0 / 10000) <= 12 then '(8-12]'
        when (seller_model_price * 1.0 / 10000) > 12  then '(12+)'
    end as model_price_region, -- 价格段
    case when fuel_type in (12,13,20) then '新能源' else '燃油车' end as fuel_type, -- 燃油类型
    count(distinct clue_id) as `上架量`,
    count(distinct case when org_base_price >0 then clue_id end) as `有原始底价的上架量`,
    count(distinct case when org_base_price >0 then clue_id end) * 1.0 / count(distinct clue_id) as `车主原始心理底价覆盖率`,
    sum(org_base_price) as `车主原始心理底价`,
    sum(seller_model_price) as `上架时车主到手模型价`,
    sum(org_base_price * 1.0 / case when org_base_price >0 then seller_model_price else 0 end) as `车主预期偏离度`
	
from guazi_dw_dwd.dim_ctob_auction_car_source_ymd
where dt ='${date_y_m_d}' 
and substring(onshelf_time, 1, 10) between '${start}' and '${date_y_m_d}'
and ctob_busi_type_code in (0,1)
group by 1, 2, 3