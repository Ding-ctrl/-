# 第15章 Linux 内核电源管理框架

## 15.1 引言

低功耗设计不仅仅是硬件的工作——在现代 SoC 中，**软件电源管理**对最终功耗表现有决定性影响。Linux 内核提供了一套成熟的电源管理框架，负责在运行时动态控制 CPU 频率/电压、外设电源状态、系统休眠等。作为低功耗设计专家，理解这些软件框架如何与底层硬件交互，是实现软硬件协同优化的关键。

## 15.2 Linux 电源管理架构全景

### 15.2.1 框架层次

```
Linux电源管理架构:

┌─────────────────────────────────────────────────┐
│                用户空间 (User Space)              │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐ │
│  │ PowerTOP │ │ sysfs    │ │ Android         │ │
│  │ 功耗分析 │ │ 接口     │ │ PowerManager    │ │
│  └──────────┘ └──────────┘ └──────────────────┘ │
├─────────────────────────────────────────────────┤
│                内核空间 (Kernel Space)            │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │  电源管理核心 (PM Core)                    │   │
│  │  ├── CPUFreq (CPU频率/电压调节)           │   │
│  │  ├── CPUIdle (CPU空闲状态管理)            │   │
│  │  ├── PM Runtime (运行时设备电源管理)       │   │
│  │  ├── System Suspend (系统休眠)            │   │
│  │  ├── PM Domains (电源域管理)              │   │
│  │  ├── Devfreq (设备频率调节)               │   │
│  │  ├── Energy Model (能量模型)              │   │
│  │  └── Thermal (热管理)                     │   │
│  └──────────────────────────────────────────┘   │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │  平台驱动层 (Platform Drivers)             │   │
│  │  ├── PMIC 驱动 (Regulator Framework)      │   │
│  │  ├── Clock 驱动 (Common Clock Framework)  │   │
│  │  ├── Reset 驱动                           │   │
│  │  └── Platform PM Ops                      │   │
│  └──────────────────────────────────────────┘   │
├─────────────────────────────────────────────────┤
│                硬件 (Hardware)                    │
│  ┌──────────┐ ┌──────┐ ┌──────┐ ┌──────────┐   │
│  │   PMIC   │ │ PLL  │ │ PMU  │ │ Thermal  │   │
│  │          │ │ Clock│ │      │ │ Sensor   │   │
│  └──────────┘ └──────┘ └──────┘ └──────────┘   │
└─────────────────────────────────────────────────┘
```

## 15.3 CPUFreq 框架

### 15.3.1 CPUFreq 架构

```
CPUFreq 框架结构:

┌─────────────────────────────────────────┐
│  CPUFreq Governor (调频策略)              │
│  ├── performance  (最高频率)             │
│  ├── powersave    (最低频率)             │
│  ├── ondemand     (按需调频)             │
│  ├── conservative (保守调频)             │
│  ├── schedutil    (调度器驱动, 推荐)     │
│  └── userspace    (用户空间控制)          │
├─────────────────────────────────────────┤
│  CPUFreq Core                            │
│  ├── 频率表管理                          │
│  ├── 策略(Policy)管理                    │
│  ├── 频率切换协调                        │
│  └── sysfs 接口                          │
├─────────────────────────────────────────┤
│  CPUFreq Driver (平台驱动)               │
│  ├── cpufreq-dt (Device Tree通用)        │
│  ├── intel_pstate                        │
│  ├── arm_scmi_cpufreq                    │
│  └── 自定义平台驱动                      │
└─────────────────────────────────────────┘
```

### 15.3.2 CPUFreq Driver 开发

```c
/*
 * 示例: 简化的CPUFreq平台驱动
 * 适用于自定义SoC的DVFS控制
 */

#include <linux/cpufreq.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/regulator/consumer.h>
#include <linux/clk.h>

struct my_soc_cpufreq {
    struct clk *cpu_clk;
    struct regulator *cpu_reg;
    struct cpufreq_frequency_table *freq_table;
};

/* OPP (Operating Performance Point) 表 */
/* 通常从Device Tree加载 */
static struct cpufreq_frequency_table opp_table[] = {
    { .frequency = 200000,  /* 200 MHz, 0.7V */ },
    { .frequency = 500000,  /* 500 MHz, 0.8V */ },
    { .frequency = 800000,  /* 800 MHz, 0.9V */ },
    { .frequency = 1000000, /* 1.0 GHz, 1.0V */ },
    { .frequency = 1200000, /* 1.2 GHz, 1.1V */ },
    { .frequency = CPUFREQ_TABLE_END },
};

/* 电压表 (与频率表对应) */
static unsigned int voltage_table[] = {
    700000,  /* 0.7V for 200MHz */
    800000,  /* 0.8V for 500MHz */
    900000,  /* 0.9V for 800MHz */
    1000000, /* 1.0V for 1.0GHz */
    1100000, /* 1.1V for 1.2GHz */
};

static int my_cpufreq_target(struct cpufreq_policy *policy,
                              unsigned int target_freq,
                              unsigned int relation)
{
    struct my_soc_cpufreq *priv = policy->driver_data;
    unsigned int old_freq, new_freq;
    unsigned int old_volt, new_volt;
    int idx, ret;

    /* 找到目标频率对应的索引 */
    ret = cpufreq_frequency_table_target(policy,
            opp_table, target_freq, relation, &idx);
    if (ret)
        return ret;

    new_freq = opp_table[idx].frequency;
    new_volt = voltage_table[idx];
    old_freq = clk_get_rate(priv->cpu_clk) / 1000;

    if (old_freq == new_freq)
        return 0;

    /* DVFS切换: 升频先升压, 降频先降频 */
    if (new_freq > old_freq) {
        /* 升频: 先提高电压 */
        ret = regulator_set_voltage(priv->cpu_reg,
                new_volt, new_volt + 50000);
        if (ret)
            return ret;

        /* 再提高频率 */
        ret = clk_set_rate(priv->cpu_clk,
                           new_freq * 1000);
    } else {
        /* 降频: 先降低频率 */
        ret = clk_set_rate(priv->cpu_clk,
                           new_freq * 1000);
        if (ret)
            return ret;

        /* 再降低电压 */
        ret = regulator_set_voltage(priv->cpu_reg,
                new_volt, new_volt + 50000);
    }

    return ret;
}

static struct cpufreq_driver my_cpufreq_driver = {
    .name     = "my-soc-cpufreq",
    .flags    = CPUFREQ_NEED_INITIAL_FREQ_CHECK,
    .init     = my_cpufreq_init,
    .verify   = cpufreq_generic_frequency_table_verify,
    .target   = my_cpufreq_target,
    .get      = cpufreq_generic_get,
    .attr     = cpufreq_generic_attr,
};
```

### 15.3.3 Device Tree 中的 OPP 定义

```dts
/* Device Tree OPP定义 */
cpu_opp_table: opp-table {
    compatible = "operating-points-v2";
    
    opp-200000000 {
        opp-hz = /bits/ 64 <200000000>;
        opp-microvolt = <700000>;
        opp-supported-hw = <0xff>;
    };
    
    opp-500000000 {
        opp-hz = /bits/ 64 <500000000>;
        opp-microvolt = <800000>;
    };
    
    opp-800000000 {
        opp-hz = /bits/ 64 <800000000>;
        opp-microvolt = <900000>;
    };
    
    opp-1000000000 {
        opp-hz = /bits/ 64 <1000000000>;
        opp-microvolt = <1000000>;
    };
    
    opp-1200000000 {
        opp-hz = /bits/ 64 <1200000000>;
        opp-microvolt = <1100000>;
        turbo-mode;  /* 标记为Turbo频率 */
    };
};

cpus {
    cpu@0 {
        compatible = "arm,cortex-a55";
        operating-points-v2 = <&cpu_opp_table>;
        cpu-supply = <&cpu_regulator>;
        clocks = <&cpu_clk>;
    };
};
```

### 15.3.4 schedutil Governor

```
schedutil Governor 工作原理:

传统Governor (ondemand):
  ├── 周期性采样CPU利用率 (每10-100ms)
  ├── 利用率高 → 升频
  ├── 利用率低 → 降频
  └── 问题: 响应延迟, 采样开销

schedutil Governor (推荐):
  ├── 直接从调度器获取利用率信息
  ├── 每次任务调度时更新 (无需额外采样)
  ├── 响应速度更快
  └── 与EAS (Energy Aware Scheduling) 协同

频率选择公式:
  freq_next = freq_max × (util / max_util)
  
  其中:
    util     = 当前CPU利用率
    max_util = CPU最大利用率能力
```

## 15.4 CPUIdle 框架

### 15.4.1 CPU 空闲状态层次

```
ARM CPU 空闲状态层次:

C0: Active      ── 正常运行
 │
C1: WFI         ── 等待中断 (Wait For Interrupt)
 │                  时钟门控核心, 唤醒: ~1μs
 │
C2: Core Ret    ── 核心保持 (Core Retention)
 │                  核心掉电+状态保持, 唤醒: ~10μs
 │
C3: Core Off    ── 核心关断 (Core Power Off)
 │                  核心完全关断, 唤醒: ~100μs
 │
C4: Cluster Ret ── 集群保持 (Cluster Retention)
 │                  集群掉电+L2保持, 唤醒: ~500μs
 │
C5: Cluster Off ── 集群关断 (Cluster Power Off)
                    集群完全关断, 唤醒: ~1ms

越深的状态:
  ├── 功耗越低
  ├── 唤醒延迟越大
  └── 唤醒能量越大 (需要恢复上下文)
```

### 15.4.2 CPUIdle Governor

```
CPUIdle Governor选择空闲状态的决策:

menu Governor (默认):
  ├── 预测下一次唤醒时间
  ├── 选择满足延迟约束的最深状态
  └── 考虑能量收支平衡
  
TEO (Timer Events Oriented) Governor:
  ├── 分析历史定时器事件模式
  ├── 更准确的睡眠时间预测
  └── 适合定时器密集的工作负载

haltpoll Governor:
  ├── 适合虚拟化环境
  └── 先轮询再进入深度睡眠

决策公式:
  选择状态Ci, 满足:
    1. target_residency(Ci) < 预测空闲时间
    2. exit_latency(Ci) < QoS延迟约束
    3. energy_saved(Ci) > energy_cost(Ci)
```

### 15.4.3 CPUIdle Driver 示例

```c
/*
 * CPUIdle Driver 关键结构
 */

static struct cpuidle_state my_idle_states[] = {
    {
        .name = "WFI",
        .desc = "ARM Wait For Interrupt",
        .exit_latency = 1,        /* 1 μs */
        .target_residency = 5,     /* 至少5μs才值得进入 */
        .enter = my_enter_wfi,
        .flags = CPUIDLE_FLAG_POLLING,
    },
    {
        .name = "CORE_RET",
        .desc = "Core Retention",
        .exit_latency = 50,        /* 50 μs */
        .target_residency = 200,   /* 至少200μs */
        .enter = my_enter_core_retention,
    },
    {
        .name = "CORE_OFF",
        .desc = "Core Power Off",
        .exit_latency = 200,       /* 200 μs */
        .target_residency = 1000,  /* 至少1ms */
        .enter = my_enter_core_off,
    },
    {
        .name = "CLUSTER_OFF",
        .desc = "Cluster Power Off",
        .exit_latency = 1000,      /* 1 ms */
        .target_residency = 5000,  /* 至少5ms */
        .enter = my_enter_cluster_off,
    },
};

static int my_enter_core_retention(
    struct cpuidle_device *dev,
    struct cpuidle_driver *drv, int index)
{
    /* 1. 保存CPU上下文 */
    cpu_pm_enter();

    /* 2. 通知PMU进入core retention */
    writel(CORE_RET_MODE, pmu_base + PMU_CTRL);

    /* 3. 执行WFI (实际进入低功耗状态) */
    cpu_do_idle();

    /* 4. 唤醒后恢复 */
    cpu_pm_exit();

    return index;
}
```

## 15.5 PM Runtime (运行时电源管理)

### 15.5.1 PM Runtime 概念

```
PM Runtime 框架:

目标: 自动管理设备(外设)的运行时电源状态
  - 设备空闲时自动关断
  - 需要时自动唤醒
  - 无需修改设备使用者的代码

状态机:
  ┌─────────┐  pm_runtime_get()  ┌─────────┐
  │         │ ─────────────────► │         │
  │ Suspend │                    │  Active │
  │ (关断)  │ ◄───────────────── │ (活跃)  │
  │         │  pm_runtime_put()  │         │
  └─────────┘                    └─────────┘
       │                              │
       │     autosuspend_delay        │
       │ ◄─────────────────────────── │
       │    (自动延迟关断)              │
```

### 15.5.2 PM Runtime Driver 实现

```c
/*
 * PM Runtime 设备驱动示例
 * 以UART控制器为例
 */

static int my_uart_runtime_suspend(struct device *dev)
{
    struct my_uart_priv *priv = dev_get_drvdata(dev);

    /* 1. 关闭设备时钟 */
    clk_disable_unprepare(priv->clk);

    /* 2. (可选)降低电压或关断电源 */
    regulator_disable(priv->reg);

    dev_dbg(dev, "UART runtime suspended\n");
    return 0;
}

static int my_uart_runtime_resume(struct device *dev)
{
    struct my_uart_priv *priv = dev_get_drvdata(dev);
    int ret;

    /* 1. 恢复电源 */
    ret = regulator_enable(priv->reg);
    if (ret)
        return ret;

    /* 2. 恢复时钟 */
    ret = clk_prepare_enable(priv->clk);
    if (ret) {
        regulator_disable(priv->reg);
        return ret;
    }

    dev_dbg(dev, "UART runtime resumed\n");
    return 0;
}

static const struct dev_pm_ops my_uart_pm_ops = {
    SET_RUNTIME_PM_OPS(
        my_uart_runtime_suspend,
        my_uart_runtime_resume,
        NULL)
    SET_SYSTEM_SLEEP_PM_OPS(
        my_uart_system_suspend,
        my_uart_system_resume)
};

/* 在probe中启用Runtime PM */
static int my_uart_probe(struct platform_device *pdev)
{
    /* ... 初始化 ... */

    /* 启用Runtime PM */
    pm_runtime_enable(&pdev->dev);

    /* 设置自动延迟关断 (500ms空闲后关断) */
    pm_runtime_set_autosuspend_delay(&pdev->dev, 500);
    pm_runtime_use_autosuspend(&pdev->dev);

    return 0;
}

/* 在UART操作中使用 */
static int my_uart_send(struct my_uart_priv *priv,
                         const char *buf, int len)
{
    /* 唤醒设备 */
    pm_runtime_get_sync(priv->dev);

    /* 发送数据 */
    /* ... */

    /* 释放设备 (如果空闲则自动关断) */
    pm_runtime_mark_last_busy(priv->dev);
    pm_runtime_put_autosuspend(priv->dev);

    return len;
}
```

## 15.6 PM Domains (电源域管理)

### 15.6.1 Generic PM Domain (genpd)

```
Linux PM Domain 框架:

                    ┌─────────────────┐
                    │ PM Domain Core  │
                    │ (genpd)         │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
        ┌─────▼─────┐ ┌─────▼─────┐ ┌─────▼─────┐
        │ PD_CPU    │ │ PD_GPU    │ │ PD_PERIPH │
        │           │ │           │ │           │
        │ cpu@0     │ │ gpu@0     │ │ uart@0   │
        │ cpu@1     │ │           │ │ spi@0    │
        │ l2-cache  │ │           │ │ i2c@0    │
        └───────────┘ └───────────┘ └───────────┘

genpd 关键特性:
  - 自动聚合子设备电源请求
  - 所有子设备idle → 自动关断域
  - 任一子设备active → 自动打开域
  - 支持域层次结构 (父域/子域)
  - 支持域间依赖关系
```

### 15.6.2 genpd Device Tree 定义

```dts
/* Device Tree中定义电源域 */
power_domains: power-controller@10000 {
    compatible = "my-soc,power-domains";
    reg = <0x10000 0x1000>;
    #power-domain-cells = <1>;
    
    /* 域定义 */
    pd_cpu: power-domain@0 {
        #power-domain-cells = <0>;
    };
    
    pd_gpu: power-domain@1 {
        #power-domain-cells = <0>;
    };
    
    pd_periph: power-domain@2 {
        #power-domain-cells = <0>;
        /* 父域: Always-On */
        power-domains = <&power_domains 0>;
    };
};

/* 设备关联到电源域 */
uart0: serial@20000 {
    compatible = "my-soc,uart";
    reg = <0x20000 0x100>;
    clocks = <&uart_clk>;
    power-domains = <&pd_periph>;  /* 属于外设电源域 */
};

gpu: gpu@30000 {
    compatible = "my-soc,gpu";
    reg = <0x30000 0x10000>;
    power-domains = <&pd_gpu>;     /* 属于GPU电源域 */
};
```

## 15.7 System Suspend (系统休眠)

### 15.7.1 休眠状态层次

```
Linux系统休眠状态:

状态           描述                    唤醒时间    功耗
─────────────────────────────────────────────────────
Freeze         冻结进程+设备idle       ~100ms      中
  (s2idle)     CPU进入最深idle

Standby        Freeze + 非引导CPU离线  ~1s         低
  (shallow)    

Suspend-to-RAM 所有设备suspend         ~2s         很低
  (S3/mem)     CPU/DDR进入自刷新

Suspend-to-Disk 状态写入磁盘           ~10s        零
  (S4/disk)     完全掉电 (hibernate)

进入流程:
  用户写入 → PM Core → 设备suspend → CPU进入低功耗
  echo mem > /sys/power/state
```

### 15.7.2 Suspend/Resume 流程

```
Suspend 流程:

1. echo mem > /sys/power/state
   │
2. freeze_processes()
   │  冻结所有用户进程和可冻结内核线程
   │
3. suspend_devices_and_enter()
   │  ├── dpm_suspend_start()
   │  │    各设备驱动 .suspend() 回调
   │  │    (按设备树逆序)
   │  │
   │  ├── dpm_suspend_noirq()
   │  │    关闭中断后的设备suspend
   │  │
   │  ├── syscore_suspend()
   │  │    核心子系统suspend (时钟,中断控制器等)
   │  │
   │  └── suspend_enter()
   │       ├── 非引导CPU离线
   │       ├── 引导CPU执行WFI
   │       └── 等待唤醒中断
   │
4. ════════════ 系统进入低功耗状态 ════════════
   │
5. 唤醒中断到达
   │
6. resume (逆序恢复)
   │  ├── syscore_resume()
   │  ├── dpm_resume_noirq()
   │  ├── dpm_resume()
   │  └── thaw_processes()
```

## 15.8 Regulator Framework (电压调节器框架)

### 15.8.1 Regulator 架构

```
Regulator Framework:

Consumer (使用者):
  cpu_supply, gpu_supply, io_supply ...
        │         │         │
        ▼         ▼         ▼
┌──────────────────────────────────┐
│  Regulator Core                  │
│  ├── 约束管理 (电压范围, 电流)    │
│  ├── 引用计数 (多consumer共享)   │
│  ├── 级联管理 (regulator树)      │
│  └── sysfs 调试接口              │
└──────────────┬───────────────────┘
               │
        ┌──────▼──────┐
        │ PMIC Driver │
        │ (I²C/SPI)   │
        └──────┬──────┘
               │
        ┌──────▼──────┐
        │   PMIC HW   │
        │  (TPS65xxx, │
        │   AXP, etc.)│
        └─────────────┘
```

### 15.8.2 Regulator Driver 关键操作

```c
/* Regulator操作接口 */
static struct regulator_ops my_reg_ops = {
    /* 开/关 */
    .enable           = my_reg_enable,
    .disable          = my_reg_disable,
    .is_enabled       = my_reg_is_enabled,
    
    /* 电压控制 */
    .set_voltage_sel  = my_reg_set_voltage_sel,
    .get_voltage_sel  = my_reg_get_voltage_sel,
    .list_voltage     = regulator_list_voltage_linear,
    
    /* 模式控制 */
    .set_mode         = my_reg_set_mode,
    .get_mode         = my_reg_get_mode,
    
    /* 电流限制 */
    .set_current_limit = my_reg_set_current_limit,
};

/* Consumer使用示例 */
struct regulator *cpu_reg;

/* 获取regulator */
cpu_reg = devm_regulator_get(dev, "cpu");

/* 设置电压 */
regulator_set_voltage(cpu_reg, 900000, 950000);

/* 启用 */
regulator_enable(cpu_reg);
```

## 15.9 Common Clock Framework (时钟框架)

### 15.9.1 时钟树管理

```
Linux时钟框架:

              24MHz OSC
                 │
         ┌───────▼───────┐
         │    PLL0       │
         │  (1.2 GHz)    │
         └───────┬───────┘
                 │
       ┌─────────┼─────────┐
       │         │         │
    ┌──▼──┐  ┌──▼──┐  ┌──▼──┐
    │DIV/2│  │DIV/4│  │DIV/8│
    │600M │  │300M │  │150M │
    └──┬──┘  └──┬──┘  └──┬──┘
       │        │        │
    ┌──▼──┐  ┌──▼──┐  ┌──▼──┐
    │ MUX │  │GATE │  │GATE │
    │ CPU │  │ GPU │  │UART │
    └─────┘  └─────┘  └─────┘

Clock Framework 低功耗特性:
  - clk_disable(): 关闭时钟门控 → 零动态功耗
  - clk_set_rate(): 调频
  - 引用计数: 无consumer使用时自动关闭
  - 父时钟级联: 子时钟全关 → 父时钟可关
```

## 15.10 Energy Aware Scheduling (EAS)

### 15.10.1 EAS 概念

```
Energy Aware Scheduling (能量感知调度):

传统调度: 只考虑性能和公平性
EAS调度:  在性能前提下, 最小化能量消耗

关键组件:
  1. Energy Model (EM): 描述每个CPU在各OPP下的功耗
  2. Capacity: 描述每个CPU的计算能力
  3. 调度器: 选择总能量最低的CPU放置任务

决策过程:
  新任务到达 → 评估放在每个CPU上的能量成本
              → 选择总能量增量最小的CPU

示例 (big.LITTLE):
  任务: 需要100 capacity
  
  放在big核:   1000MHz × 1.0V → 200 mW
  放在LITTLE核: 800MHz × 0.8V → 50 mW  ← EAS选这个!
```

### 15.10.2 Energy Model 定义

```c
/* 能量模型注册 */
static struct em_perf_state cpu_little_states[] = {
    /* freq(kHz), power(mW), cost */
    { 200000,   25,  0 },
    { 500000,   80,  0 },
    { 800000,  150,  0 },
    { 1000000, 250,  0 },
};

/* Device Tree方式定义能量模型 */
/* 参见 Documentation/power/energy-model.rst */
```

## 15.11 Thermal Framework (热管理)

### 15.11.1 热管理架构

```
Linux Thermal Framework:

    ┌──────────────────────────────┐
    │ Thermal Governor             │
    │  ├── step_wise (逐步降频)    │
    │  ├── power_allocator (IPA)   │
    │  └── user_space              │
    └──────────────┬───────────────┘
                   │
    ┌──────────────▼───────────────┐
    │ Thermal Zone                 │
    │  温度传感器 → 当前温度        │
    │  Trip Points → 温度阈值      │
    └──────────────┬───────────────┘
                   │
    ┌──────────────▼───────────────┐
    │ Cooling Devices              │
    │  ├── cpufreq_cooling (限频)  │
    │  ├── devfreq_cooling (GPU)   │
    │  ├── thermal_of_cooling (风扇)│
    │  └── power_allocator         │
    └──────────────────────────────┘

Trip Points 定义:
  passive: 80°C → 开始降频
  active:  70°C → 开启风扇
  critical: 110°C → 紧急关机
```

### 15.11.2 Intelligent Power Allocation (IPA)

```
IPA (智能功耗分配):

目标: 在温度约束下, 将功耗预算分配给各组件

                温度目标 (如 85°C)
                     │
              ┌──────▼──────┐
              │ PID 控制器   │
              │ P_budget     │
              └──────┬──────┘
                     │
           ┌─────────┼─────────┐
           │         │         │
     ┌─────▼────┐┌───▼────┐┌──▼──────┐
     │ CPU      ││ GPU    ││ 其他     │
     │ P_cpu    ││ P_gpu  ││ P_other  │
     └──────────┘└────────┘└─────────┘
     
     约束: P_cpu + P_gpu + P_other ≤ P_budget
     
     分配策略: 按各组件的功耗效率比例分配
     效率 = performance / power
```

## 15.12 调试与分析工具

### 15.12.1 功耗调试命令

```bash
# 查看CPU频率
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq

# 查看所有CPU OPP
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies

# 设置Governor
echo schedutil > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# 查看CPUIdle状态
cat /sys/devices/system/cpu/cpu0/cpuidle/state*/name
cat /sys/devices/system/cpu/cpu0/cpuidle/state*/usage
cat /sys/devices/system/cpu/cpu0/cpuidle/state*/time

# 查看电源域状态
cat /sys/kernel/debug/pm_genpd/pm_genpd_summary

# 查看Runtime PM状态
cat /sys/devices/platform/*/power/runtime_status

# 查看Regulator状态
cat /sys/kernel/debug/regulator/regulator_summary

# 查看时钟状态
cat /sys/kernel/debug/clk/clk_summary

# 使用PowerTOP分析
powertop --html=report.html
```

## 15.13 本章小结

| 框架 | 功能 | 关键文件 |
|------|------|----------|
| CPUFreq | CPU 频率/电压调节 | drivers/cpufreq/ |
| CPUIdle | CPU 空闲状态管理 | drivers/cpuidle/ |
| PM Runtime | 设备运行时电源管理 | drivers/base/power/ |
| PM Domains | 电源域聚合管理 | drivers/base/power/domain.c |
| System Suspend | 系统级休眠 | kernel/power/ |
| Regulator | 电压调节器框架 | drivers/regulator/ |
| Clock | 时钟树管理 | drivers/clk/ |
| Thermal | 热管理与功耗分配 | drivers/thermal/ |
| EAS | 能量感知调度 | kernel/sched/ |

**下一章**将介绍 Android 和 RTOS 电源管理的具体实现。
