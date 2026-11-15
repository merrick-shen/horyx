/// 战场音效事件：子弹与远程驱动只上抛语义事件，
/// 播放统一由战场承载（音效语义单点维护，双端不再各自发声）
enum TankSoundEvent { shoot, wallBounce, bulletExpire, explosion }
