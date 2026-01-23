# **代码构建顺序 (Implementation Order)**

## **第一阶段：基石 (Foundation)**

**说明：** 这些脚本不依赖任何其他自定义类，只依赖 Godot 原生 API。它们是整个项目的“词汇表”和“数据结构”。

1. **Constants.gd**  
   * **依赖:** 无  
   * **作用:** 定义 TILE\_SIZE, Layer 枚举, 路径常量。所有后续脚本都会用到它。  
   * **对应文档:** arch\_04\_data\_utils.md  
2. **MapUtils.gd**  
   * **依赖:** Constants (用于计算)  
   * **作用:** 提供坐标转换静态函数。  
   * **对应文档:** arch\_04\_data\_utils.md  
3. **SignalBus.gd**  
   * **依赖:** 无  
   * **作用:** 全局信号定义。后续的管理器需要发射这些信号。  
   * **对应文档:** arch\_01\_managers.md  
4. **SaveSystem.gd**  
   * **依赖:** 无  
   * **作用:** 路径和文件管理。  
   * **对应文档:** arch\_01\_managers.md  
5. **ChunkLogic.gd**  
   * **依赖:** 无  
   * **作用:** 简单的生命周期锚点节点。  
   * **对应文档:** arch\_03\_entities.md

## **第二阶段：核心数据与输入 (Data & Input)**

**说明：** 定义核心数据模型和输入处理，开始引用第一阶段的基石。

6. **ChunkData.gd**  
   * **依赖:** Constants (可能用到 Layer 枚举)  
   * **作用:** 内存数据模型。  
   * **对应文档:** arch\_04\_data\_utils.md  
7. **InputManager.gd**  
   * **依赖:** SignalBus (发送信号), MapUtils (坐标转换)  
   * **作用:** 处理原始输入。  
   * **对应文档:** arch\_01\_managers.md

## **第三阶段：功能组件 (Components)**

**说明：** 这些是“胶水代码”，分别封装了具体的第三方插件或复杂逻辑。它们依赖前两个阶段的内容。

8. **RegionDatabase.gd**  
   * **依赖:** Godot-SQLite (插件), ChunkData  
   * **作用:** 数据库读写。  
   * **对应文档:** arch\_01\_managers.md  
9. **MapGenerator.gd**  
   * **依赖:** FastNoiseLite (资源), ChunkData  
   * **作用:** 生成地形数据。  
   * **对应文档:** arch\_01\_managers.md  
10. **GlobalMapController.gd**  
    * **依赖:** Better Terrain (插件), ChunkData, Constants  
    * **作用:** 渲染地形和物体。  
    * **对应文档:** arch\_02\_environment.md  
11. **CameraRig.gd**  
    * **依赖:** Phantom Camera (插件), InputManager  
    * **作用:** 摄像机控制。  
    * **对应文档:** arch\_03\_entities.md

## **第四阶段：实体 (Entities)**

**说明：** 玩家和 NPC，它们需要依赖输入和组件。

12. **Player.gd**  
    * **依赖:** CameraRig, StateChart (插件), NavigationAgent2D  
    * **作用:** 玩家控制逻辑。  
    * **对应文档:** arch\_03\_entities.md

## **第五阶段：核心大脑 (Core Managers)**

**说明：** 最后编写调度器，因为它们需要引用上述所有模块来指挥交通。

13. **WorldManager.gd**  
    * **依赖:** RegionDatabase, MapGenerator, GlobalMapController, SignalBus, ChunkLogic  
    * **作用:** 区块加载流水线与数据总管。  
    * **对应文档:** arch\_01\_managers.md  
14. **InteractionManager.gd**  
    * **依赖:** InputManager, SignalBus, Player, WorldManager  
    * **作用:** 游戏交互逻辑裁决。  
    * **对应文档:** arch\_01\_managers.md