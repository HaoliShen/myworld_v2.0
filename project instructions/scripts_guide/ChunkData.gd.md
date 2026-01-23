# **脚本设计: ChunkData.gd**

路径: res://Scripts/Data/ChunkData.gd  
继承: RefCounted

## **职责**

内存中存储单个区块的所有状态，是数据流转的**唯一真理 (Source of Truth)**。

## **属性**

var coord: Vector2i  
var is\_dirty: bool \= false

\# \[Layer 1 \- Data A\] 地形类型数据 (Terrain Type ID)  
\# 存储: 地面材质 ID (如 Constants.ID\_TREE\_OAK \= 300\)  
\# 类型: PackedInt32Array   
\# 理由: 使用 Int32 而非 Byte，因为物体 ID 可能超过 255 (例如 300, 400)。  
\# 访问: 直接通过索引访问，无需解压。  
var terrain\_map: PackedInt32Array 

\# \[Layer 1 \- Data B\] 地形高度数据 (Elevation Level)  
\# 存储: 绝对高度值 (0, 1, 2...)  
\# 类型: PackedByteArray  
\# 理由: 高度层级通常不会超过 255 层，使用 Byte 最省内存。  
\# 访问: elevation\_map\[index\] 直接返回整数，无需位运算。  
var elevation\_map: PackedByteArray

\# \[Layer 2 & 3\] 物体层数据 (稀疏存储)  
\# Key: int (Packed Local Coord) \-\> Value: int (Tile ID)  
\# 存储: 树木、墙壁等稀疏物体  
var object\_map: Dictionary 

## **初始化与基础接口 (API)**

\# 初始化函数  
func \_init(target\_coord: Vector2i):  
    coord \= target\_coord  
      
    \# 1\. 初始化地形 ID 数组 (32位整数)  
    terrain\_map \= PackedInt32Array()  
    terrain\_map.resize(Constants.CHUNK\_SIZE \* Constants.CHUNK\_SIZE)  
    terrain\_map.fill(-1) \# 默认空  
      
    \# 2\. 初始化高度数组 (8位字节)  
    elevation\_map \= PackedByteArray()  
    elevation\_map.resize(Constants.CHUNK\_SIZE \* Constants.CHUNK\_SIZE)  
    elevation\_map.fill(0) \# 默认高度 0

\# \--- 高度操作 (最频繁调用的逻辑) \---

\# 获取高度  
\# 复杂度: O(1) 直接内存访问  
func get\_elevation(x: int, y: int) \-\> int:  
    \# 安全检查省略，追求性能可直接访问  
    return elevation\_map\[y \* 32 \+ x\]

\# 设置高度  
func set\_elevation(x: int, y: int, h: int) \-\> void:  
    var idx \= y \* 32 \+ x  
    if elevation\_map\[idx\] \!= h:  
        elevation\_map\[idx\] \= h  
        is\_dirty \= true

\# \--- 地形操作 \---

func get\_terrain(x: int, y: int) \-\> int:  
    return terrain\_map\[y \* 32 \+ x\]

func set\_terrain(x: int, y: int, id: int) \-\> void:  
    var idx \= y \* 32 \+ x  
    if terrain\_map\[idx\] \!= id:  
        terrain\_map\[idx\] \= id  
        is\_dirty \= true

## **序列化接口 (Serialization)**

\# 序列化为二进制流  
\# 结构: \[Terrain(Int32) Bytes\] \+ \[Elevation(Byte) Bytes\] \+ \[Object Dictionary\]  
func to\_bytes() \-\> PackedByteArray:  
    var buffer \= StreamPeerBuffer.new()  
      
    \# 1\. 写入地形 (Int32 Array \-\> Bytes)  
    var t\_bytes \= terrain\_map.to\_byte\_array()  
    buffer.put\_32(t\_bytes.size())  
    buffer.put\_data(t\_bytes)  
      
    \# 2\. 写入高度 (Byte Array \-\> Bytes)  
    \# PackedByteArray 本身就是 Bytes，无需转换，直接写入内容  
    buffer.put\_32(elevation\_map.size())  
    buffer.put\_data(elevation\_map)  
      
    \# 3\. 写入物体 (Dictionary)  
    var o\_bytes \= var\_to\_bytes(object\_map)  
    buffer.put\_data(o\_bytes)  
      
    return buffer.data\_array

\# 反序列化  
static func from\_bytes(coord: Vector2i, data: PackedByteArray) \-\> ChunkData:  
    var instance \= ChunkData.new(coord)  
    var buffer \= StreamPeerBuffer.new()  
    buffer.data\_array \= data  
      
    \# 1\. 读取地形  
    var t\_size \= buffer.get\_32()  
    var t\_bytes \= buffer.get\_data(t\_size)\[1\]  
    instance.terrain\_map \= t\_bytes.to\_int32\_array()  
      
    \# 2\. 读取高度  
    var e\_size \= buffer.get\_32()  
    var e\_bytes \= buffer.get\_data(e\_size)\[1\]  
    instance.elevation\_map \= e\_bytes \# 直接赋值，无需转换  
      
    \# 3\. 读取物体  
    var o\_bytes\_size \= buffer.get\_available\_bytes()  
    if o\_bytes\_size \> 0:  
        var o\_bytes \= buffer.get\_data(o\_bytes\_size)\[1\]  
        instance.object\_map \= bytes\_to\_var(o\_bytes)  
          
    instance.is\_dirty \= false  
    return instance  
