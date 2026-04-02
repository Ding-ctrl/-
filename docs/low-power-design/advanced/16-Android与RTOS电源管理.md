# 第16章 Android 与 RTOS 电源管理

## 16.1 引言

在 Linux 内核电源管理框架之上，Android 和各种 RTOS 分别构建了面向特定应用场景的电源管理策略。Android 面向移动设备，需要在用户体验和电池续航之间取得平衡；RTOS 面向嵌入式设备，追求确定性的低功耗行为。本章分别介绍两者的电源管理机制。

## 16.2 Android 电源管理架构

### 16.2.1 Android 电源管理栈

```
Android 电源管理架构:

┌─────────────────────────────────────────────┐
│  应用层 (App Layer)                          │
│  ├── Battery Optimization (电池优化)         │
│  ├── JobScheduler (延迟任务调度)             │
│  └── WorkManager (工作管理器)                │
├─────────────────────────────────────────────┤
│  框架层 (Framework Layer)                    │
│  ├── PowerManagerService                     │
│  │   ├── WakeLock 管理                       │
│  │   ├── Doze 模式控制                       │
│  │   ├── App Standby Buckets                │
│  │   └── Battery Saver                       │
│  ├── DeviceIdleController (Doze)             │
│  ├── ThermalManagerService                   │
│  └── BatteryService                          │
├─────────────────────────────────────────────┤
│  HAL 层 (Hardware Abstraction Layer)         │
│  ├── power HAL (android.hardware.power)      │
│  │   └── PowerHint (性能提示)               │
│  ├── thermal HAL                             │
│  └── health HAL (电池信息)                   │
├─────────────────────────────────────────────┤
│  内核层 (Kernel Layer)                       │
│  ├── Linux PM (CPUFreq/CPUIdle/PM Runtime)   │
│  ├── Wakeup Sources (唤醒源管理)             │
│  └── Suspend Blocker (旧: early suspend)     │
└─────────────────────────────────────────────┘
```

## 16.3 WakeLock 机制

### 16.3.1 WakeLock 类型

```
Android WakeLock 类型:

┌──────────────────┬──────┬──────┬──────────────────┐
│ WakeLock 类型    │ CPU  │ 屏幕 │ 典型使用场景      │
├──────────────────┼──────┼──────┼──────────────────┤
│ PARTIAL          │ ON   │ OFF  │ 后台下载/音乐播放 │
│ FULL             │ ON   │ Bright│ 视频播放(已废弃) │
│ SCREEN_DIM       │ ON   │ Dim  │ 地图导航(已废弃)  │
│ SCREEN_BRIGHT    │ ON   │ Bright│ 相机预览(已废弃) │
│ PROXIMITY_SCREEN │ ON   │ 取决 │ 通话时靠近耳朵    │
└──────────────────┴──────┴──────┴──────────────────┘

WakeLock 对功耗的影响:
  - 持有WakeLock → 阻止系统进入Suspend → 功耗增加
  - WakeLock泄漏(忘记释放) → 电池快速耗尽
  - Android 6.0+ Doze模式可以覆盖部分WakeLock
```

### 16.3.2 WakeLock 最佳实践

```java
// ✗ 错误: 无超时WakeLock (容易泄漏)
PowerManager.WakeLock wl = pm.newWakeLock(
    PowerManager.PARTIAL_WAKE_LOCK, "MyApp:MyTask");
wl.acquire();  // 忘记release → 电池耗尽!

// ✓ 正确: 带超时的WakeLock
wl.acquire(10 * 60 * 1000);  // 最多持有10分钟

// ✓ 更好: 使用try-finally确保释放
try {
    wl.acquire(5 * 60 * 1000);
    // 执行任务...
} finally {
    if (wl.isHeld()) wl.release();
}

// ✓ 最佳: 使用WorkManager替代直接WakeLock
WorkManager.getInstance(context)
    .enqueue(OneTimeWorkRequest.Builder(MyWorker.class)
        .setConstraints(Constraints.Builder()
            .setRequiresCharging(true)  // 充电时执行
            .setRequiredNetworkType(NetworkType.UNMETERED)
            .build())
        .build());
```

## 16.4 Doze 模式

### 16.4.1 Doze 状态机

```
Android Doze 模式状态机:

屏幕关闭 + 静止不动 + 未充电
         │
    ┌────▼────┐
    │ IDLE    │ ← 正常空闲
    │ (活跃)   │
    └────┬────┘
         │ 30分钟不活动
    ┌────▼────┐
    │ IDLE_   │ ← 进入Doze预备
    │ PENDING │
    └────┬────┘
         │ 
    ┌────▼─────────┐
    │ SENSING      │ ← 检测运动传感器
    │              │
    └────┬─────────┘
         │ 确认静止
    ┌────▼─────────┐
    │ LOCATING     │ ← (可选)获取位置
    └────┬─────────┘
         │
    ┌────▼─────────┐
    │ IDLE         │ ← 深度Doze模式
    │ (Doze Deep)  │   ┌──────────────────────┐
    │              │   │ 限制:                 │
    │              ├──►│ ✗ 网络访问            │
    │              │   │ ✗ WakeLock            │
    │              │   │ ✗ AlarmManager        │
    │              │   │ ✗ WiFi扫描            │
    │              │   │ ✗ JobScheduler        │
    └──────┬───────┘   │ ✓ 高优先级FCM消息     │
           │           └──────────────────────┘
    ┌──────▼───────┐
    │ IDLE_        │ ← 维护窗口
    │ MAINTENANCE  │   (短暂允许网络/任务执行)
    └──────┬───────┘
           │
           ▼
    返回 IDLE (Doze Deep)
    维护窗口间隔递增: 1h → 2h → 4h → 6h (最大)
```

### 16.4.2 Doze 的功耗影响

```
Doze 模式功耗效果:

状态              典型功耗      vs Active   说明
────────────────────────────────────────────────
Screen On Active   300-500 mA    100%       正常使用
Screen Off Active  50-80 mA      15%        后台活跃
Light Doze         10-20 mA      4%         轻度Doze
Deep Doze          2-5 mA        1%         深度Doze

实际电池续航改善:
  无Doze:    48小时待机 (持续后台活动)
  有Doze:    7-10天待机
  改善比:    3-5×
```

## 16.5 App Standby Buckets

### 16.5.1 应用分桶策略

```
App Standby Buckets (Android 9+):

根据应用使用频率自动分类:

┌────────────┬────────────────┬─────────────────────┐
│ Bucket     │ 条件           │ 限制                │
├────────────┼────────────────┼─────────────────────┤
│ Active     │ 当前正在使用    │ 无限制              │
│ (活跃)     │                │                     │
├────────────┼────────────────┼─────────────────────┤
│ Working    │ 经常使用        │ Jobs延迟: 2小时     │
│ Set        │ (每天)         │ Alarm: 6分钟最短    │
│ (工作集)    │                │                     │
├────────────┼────────────────┼─────────────────────┤
│ Frequent   │ 定期使用        │ Jobs延迟: 8小时     │
│ (常用)      │ (每周)         │ Alarm: 30分钟最短   │
├────────────┼────────────────┼─────────────────────┤
│ Rare       │ 很少使用        │ Jobs延迟: 24小时    │
│ (稀少)      │ (每月)         │ Alarm: 2小时最短    │
│            │                │ 网络: 限制          │
├────────────┼────────────────┼─────────────────────┤
│ Restricted │ 几乎不用/       │ Jobs: 每天1次       │
│ (受限)      │ 高耗电         │ Alarm: 每天1次      │
│            │                │ 网络: 严格限制      │
└────────────┴────────────────┴─────────────────────┘
```

## 16.6 Android Thermal Framework

### 16.6.1 热管理层次

```
Android Thermal HAL 2.0:

┌─────────────────────────────────┐
│  ThermalManagerService          │
│  (Framework)                    │
│  ├── 温度监听                    │
│  ├── 热缓解策略                  │
│  └── 应用通知                    │
├─────────────────────────────────┤
│  thermal HAL 2.0                │
│  (Hardware Abstraction)         │
│  ├── 温度传感器读取              │
│  ├── 冷却设备控制                │
│  └── 热缓解级别                  │
├─────────────────────────────────┤
│  Kernel Thermal                 │
│  ├── thermal_zone               │
│  ├── cooling_device             │
│  └── IPA (Intelligent Power     │
│       Allocation)               │
└─────────────────────────────────┘

热缓解级别:
  Level 0 (None):     无操作
  Level 1 (Light):    降低亮度, 限制后台
  Level 2 (Moderate): 降频CPU/GPU
  Level 3 (Severe):   大幅限频, 关闭热点
  Level 4 (Critical): 关机保护
  Level 5 (Emergency): 紧急关机
  Level 6 (Shutdown):  立即关机
```

## 16.7 Power HAL

### 16.7.1 Power Hint 机制

```
Android Power HAL Hint:

应用/框架 → PowerManagerService → Power HAL → 内核

Hint 类型:
┌─────────────────────────┬──────────────────────────┐
│ Hint                    │ 响应动作                  │
├─────────────────────────┼──────────────────────────┤
│ INTERACTION             │ 触摸操作→短暂提升性能     │
│ LAUNCH                  │ 应用启动→全速运行         │
│ VIDEO_ENCODE            │ 视频编码→稳定高频         │
│ VIDEO_DECODE            │ 视频解码→适当提频         │
│ LOW_POWER               │ 低电量→限制最高频率       │
│ SUSTAINED_PERFORMANCE   │ 游戏→稳定不降频           │
│ VR_MODE                 │ VR模式→最低延迟           │
│ EXPENSIVE_RENDERING     │ 复杂渲染→GPU提频          │
└─────────────────────────┴──────────────────────────┘
```

### 16.7.2 Power HAL 实现示例

```cpp
// AIDL Power HAL 实现 (Android 11+)
class Power : public BnPower {
public:
    ndk::ScopedAStatus setMode(Mode type,
                                bool enabled) override {
        switch (type) {
        case Mode::LOW_POWER:
            // 设置CPU最高频率限制
            writeFile("/sys/devices/system/cpu/cpu0/"
                     "cpufreq/scaling_max_freq",
                     enabled ? "800000" : "1800000");
            // 限制GPU频率
            writeFile("/sys/class/kgsl/kgsl-3d0/"
                     "max_gpuclk",
                     enabled ? "300000000" : "710000000");
            break;

        case Mode::SUSTAINED_PERFORMANCE:
            // 稳定性能模式: 锁定中等频率
            writeFile("/sys/devices/system/cpu/cpu0/"
                     "cpufreq/scaling_governor",
                     enabled ? "performance" : "schedutil");
            break;

        default:
            break;
        }
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus setBoost(Boost type,
                                 int32_t durationMs) override {
        switch (type) {
        case Boost::INTERACTION:
            // 触摸提升: 短暂最高频率
            boostCpu(durationMs > 0 ? durationMs : 500);
            break;

        case Boost::DISPLAY_UPDATE_IMMINENT:
            // 显示更新: 短暂提升
            boostGpu(100);
            break;

        default:
            break;
        }
        return ndk::ScopedAStatus::ok();
    }
};
```

## 16.8 RTOS 电源管理

### 16.8.1 RTOS 电源管理特点

```
RTOS vs Linux 电源管理对比:

┌────────────────┬──────────────────┬──────────────────┐
│ 特性           │ Linux            │ RTOS             │
├────────────────┼──────────────────┼──────────────────┤
│ 复杂度         │ 高               │ 低               │
│ 内存占用       │ MB级             │ KB级             │
│ 启动时间       │ 秒级             │ 毫秒级           │
│ 实时性         │ 弱               │ 强               │
│ 睡眠/唤醒延迟  │ 毫秒~秒          │ 微秒~毫秒        │
│ 功耗管理粒度   │ 粗(框架级)       │ 细(应用直接控制) │
│ 适用设备       │ 手机/嵌入式      │ MCU/传感器       │
│ 典型功耗       │ mW~W             │ μW~mW           │
└────────────────┴──────────────────┴──────────────────┘
```

### 16.8.2 FreeRTOS 低功耗模式

```c
/*
 * FreeRTOS Tickless Idle 实现
 */

/* 配置: 启用Tickless Idle */
#define configUSE_TICKLESS_IDLE    2  /* 自定义实现 */
#define configEXPECTED_IDLE_TIME_BEFORE_SLEEP  2

/*
 * 自定义Tickless Idle Hook
 * 当所有任务空闲时调用
 */
void vPortSuppressTicksAndSleep(
    TickType_t xExpectedIdleTime)
{
    uint32_t sleep_ticks;
    
    /* 1. 计算可以睡眠的时间 */
    sleep_ticks = xExpectedIdleTime;
    
    /* 2. 停止SysTick定时器 */
    SysTick->CTRL &= ~SysTick_CTRL_ENABLE_Msk;
    
    /* 3. 配置低功耗定时器唤醒 */
    configure_lptimer_wakeup(sleep_ticks);
    
    /* 4. 根据睡眠时间选择低功耗模式 */
    if (sleep_ticks > DEEP_SLEEP_THRESHOLD) {
        /* 长时间空闲: 进入深度睡眠 */
        enter_deep_sleep_mode();
    } else if (sleep_ticks > SLEEP_THRESHOLD) {
        /* 中等空闲: 进入睡眠模式 */
        enter_sleep_mode();
    } else {
        /* 短暂空闲: WFI */
        __WFI();
    }
    
    /* 5. 唤醒后: 恢复SysTick */
    uint32_t actual_sleep = get_lptimer_elapsed();
    
    /* 6. 补偿Tick计数 */
    vTaskStepTick(actual_sleep);
    
    /* 7. 重新启动SysTick */
    SysTick->CTRL |= SysTick_CTRL_ENABLE_Msk;
}
```

### 16.8.3 Zephyr RTOS 电源管理

```c
/*
 * Zephyr RTOS Power Management
 */

/* 设备电源管理 */
static int my_sensor_pm_action(const struct device *dev,
                                enum pm_device_action action)
{
    switch (action) {
    case PM_DEVICE_ACTION_SUSPEND:
        /* 关闭传感器, 进入低功耗 */
        sensor_power_down(dev);
        return 0;
        
    case PM_DEVICE_ACTION_RESUME:
        /* 恢复传感器 */
        sensor_power_up(dev);
        return 0;
        
    default:
        return -ENOTSUP;
    }
}

/* 系统电源策略 */
/* Zephyr支持多种策略: */
/* PM_STATE_ACTIVE       - 活跃 */
/* PM_STATE_RUNTIME_IDLE - 运行时空闲 */
/* PM_STATE_SUSPEND_TO_IDLE - 轻度休眠 */
/* PM_STATE_STANDBY      - 待机 */
/* PM_STATE_SUSPEND_TO_RAM - 深度休眠 */
/* PM_STATE_SOFT_OFF     - 软关机 */

/* 电源策略配置 (Device Tree) */
/*
 * power-states {
 *     idle: idle {
 *         compatible = "zephyr,power-state";
 *         power-state-name = "suspend-to-idle";
 *         min-residency-us = <100>;
 *         exit-latency-us = <10>;
 *     };
 *     standby: standby {
 *         compatible = "zephyr,power-state";
 *         power-state-name = "standby";
 *         min-residency-us = <1000>;
 *         exit-latency-us = <100>;
 *     };
 * };
 */
```

## 16.9 低功耗蓝牙 (BLE) 电源管理

### 16.9.1 BLE 连接参数与功耗

```
BLE 连接参数对功耗的影响:

参数                    范围            功耗影响
────────────────────────────────────────────────
Connection Interval    7.5ms~4s        核心参数
  短间隔(7.5ms): 高吞吐, 高功耗
  长间隔(1s):    低吞吐, 低功耗

Slave Latency          0~499           允许跳过N个连接事件
  latency=0:  每个事件都响应
  latency=9:  每10个事件响应一次

Supervision Timeout    100ms~32s       连接超时

典型功耗场景:
┌──────────────────┬────────┬─────────┬────────────┐
│ 场景             │ CI     │ Latency │ 平均电流   │
├──────────────────┼────────┼─────────┼────────────┤
│ 实时交互 (游戏)  │ 7.5ms  │ 0       │ ~5 mA      │
│ 普通通知         │ 100ms  │ 4       │ ~100 μA    │
│ 环境传感器       │ 1s     │ 9       │ ~15 μA     │
│ 心率监测         │ 500ms  │ 4       │ ~30 μA     │
│ 资产追踪(广播)   │ N/A    │ N/A     │ ~5 μA      │
└──────────────────┴────────┴─────────┴────────────┘
```

## 16.10 本章小结

| 主题 | 关键要点 |
|------|----------|
| Android架构 | PowerManager→HAL→内核 三层电源管理 |
| WakeLock | 阻止系统休眠，是Android功耗问题的主要来源 |
| Doze模式 | 静止+灭屏→限制网络/任务→大幅降低待机功耗 |
| App Standby | 按应用使用频率分桶，限制不活跃应用 |
| Thermal | 温度监控→降频/限制→保护硬件 |
| Power HAL | 性能提示机制，平衡性能与功耗 |
| FreeRTOS | Tickless Idle 消除定时器中断功耗 |
| Zephyr | 结构化的设备/系统电源管理 |
| BLE | 连接参数直接决定无线通信功耗 |

**下一章**将介绍软硬件协同低功耗优化方法。
