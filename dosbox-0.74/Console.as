package com.adobe.flascc
{
  import flash.display.Bitmap
  import flash.display.BitmapData
  import flash.display.DisplayObjectContainer;
  import flash.display.Sprite;
  import flash.display.StageScaleMode;
  import flash.events.Event;
  import flash.events.KeyboardEvent;
  import flash.events.MouseEvent;
  import flash.events.SampleDataEvent;
  import flash.geom.Rectangle
  import flash.media.Sound;
  import flash.media.SoundChannel;
  import flash.net.LocalConnection;
  import flash.net.URLRequest;
  import flash.text.TextField;
  import flash.utils.ByteArray;
  import flash.utils.getTimer;
  import flash.profiler.Telemetry;

  import C_Run.ram;
  import C_Run.threadArbCondNotifyAll;
  import com.adobe.flascc.vfs.*;  
  

  /**
  * A basic implementation of a console for flascc apps.
  * The PlayerKernel class delegates to this for things like read/write
  * so that console output can be displayed in a TextField on the Stage.
  */
  public class Console extends Sprite implements ISpecialFile
  {
    private static const _height:int = 768 + 100;
    private static const _width:int = 1024;

    public var mx:int = 0, my:int = 0;
    public var sndDataBuffer:ByteArray = null

    private var _tf:TextField;
    private var bm:Bitmap
    private var enableConsole:Boolean = false
    private var frameCount:int = 0;
    private var enginetickptr:int, engineticksoundptr:int
    private var inputContainer
    private var bmd:BitmapData
    private var bmr:Rectangle
    private var keybytes:ByteArray = new ByteArray()
    private var last_mx:int = 0, last_my:int = 0
    private var snd:Sound = null
    private var sndChan:SoundChannel = null
    private var vbuffer:int, vgl_mx:int, vgl_my:int, kp:int
    private const emptyArgs:Vector.<int> = new Vector.<int>;

    /**
    * To Support the preloader case you might want to have the Console
    * act as a child of some other DisplayObjectContainer.
    */
    public function Console(container:DisplayObjectContainer = null)
    {
      CModule.rootSprite = container ? container.root : this

      if(container) {
        container.addChild(this)
        init(null)
      } else {
        addEventListener(Event.ADDED_TO_STAGE, init)
      }
    }

    /**
    * All of the real flascc init happens in this method
    * which is either run on startup or once the SWF has
    * been added to the stage.
    */
    protected function init(e:Event):void
    {
      inputContainer = new Sprite()
      addChild(inputContainer)

      addEventListener(Event.ENTER_FRAME, enterFrame)

      stage.addEventListener(KeyboardEvent.KEY_DOWN, bufferKeyDown);
      stage.addEventListener(KeyboardEvent.KEY_UP, bufferKeyUp);
      stage.addEventListener(MouseEvent.MOUSE_MOVE, bufferMouseMove);
      stage.frameRate = 60
      stage.scaleMode = StageScaleMode.NO_SCALE
      bmd = new BitmapData(1024,768)
      bm = new Bitmap(bmd)
      bmr = new Rectangle(0,0,bmd.width, bmd.height)
      bmd.fillRect(bmd.rect, 0);
      inputContainer.addChild(bm)

      if(enableConsole) {
        _tf = new TextField
        _tf.multiline = true
        _tf.width = stage.stageWidth
        _tf.height = stage.stageHeight 
        inputContainer.addChild(_tf)
      }

      try
      {
        CModule.vfs.console = this;
        CModule.vfs.addBackingStore(new com.adobe.flascc.vfs.RootFSBackingStore(), null)

        CModule.startBackground(this,
              //new <String>["dosbox", "/scorch/SCORCH.EXE", "-cycles=max"],
              new <String>["dosbox", "/duke3d_install/DUKE3D/DUKE3D.EXE"],
              new <String>[])
      }
      catch(e:*)
      {
        // If main gives any exceptions make sure we get a full stack trace
        // in our console
        consoleWrite(e.toString() + "\n" + e.getStackTrace().toString())
        throw e
      }
      vbuffer = CModule.getPublicSymbol("__avm2_vgl_argb_buffer")
      vgl_mx = CModule.getPublicSymbol("vgl_cur_mx")
      vgl_my = CModule.getPublicSymbol("vgl_cur_my")
    }

    /**
    * The callback to call when flascc code calls the posix exit() function. Leave null to exit silently.
    * @private
    */
    public var exitHook:Function;

    /**
    * The PlayerKernel implementation will use this function to handle
    * C process exit requests
    */
    public function exit(code:int):Boolean
    {
      // default to unhandled
      return exitHook ? exitHook(code) : false;
    }

    /**
    * The PlayerKernel implementation will use this function to handle
    * C IO write requests to the file "/dev/tty" (e.g. output from
    * printf will pass through this function). See the ISpecialFile
    * documentation for more information about the arguments and return value.
    */
    public function write(fd:int, bufPtr:int, nbyte:int, errnoPtr:int):int
    {
      var str:String = CModule.readString(bufPtr, nbyte)
      consoleWrite(str)
      return nbyte
    }

    public function read(fd:int, bufPtr:int, nbyte:int, errnoPtr:int):int
    {
      if(fd == 0 && nbyte == 1) {
        keybytes.position = kp++
        if(keybytes.bytesAvailable) {
          CModule.write8(bufPtr, keybytes.readUnsignedByte())
        } else {
        keybytes.position = 0
        kp = 0
        }
      }
      return 0
    }

    /**
    * The PlayerKernel implementation will use this function to handle
    * C fcntl requests to the file "/dev/tty" 
    * See the ISpecialFile documentation for more information about the
    * arguments and return value.
    */
    public function fcntl(fd:int, com:int, data:int, errnoPtr:int):int
    {
      return 0
    }

    /**
    * The PlayerKernel implementation will use this function to handle
    * C ioctl requests to the file "/dev/tty" 
    * See the ISpecialFile documentation for more information about the
    * arguments and return value.
    */
    public function ioctl(fd:int, com:int, data:int, errnoPtr:int):int
    {
      return CModule.callI(CModule.getPublicSymbol("vglttyioctl"), new <int>[fd, com, data, errnoPtr]);
    }

    public function bufferMouseMove(me:MouseEvent) {
      me.stopPropagation()
      mx = me.stageX
      my = me.stageY
    }

    public function bufferKeyDown(ke:KeyboardEvent) {
      ke.stopPropagation()
      keybytes.writeByte(int(ke.keyCode & 0x7F))
    }
    
    public function bufferKeyUp(ke:KeyboardEvent) {
      ke.stopPropagation()
      keybytes.writeByte(int(ke.keyCode | 0x80))
    }

    /**
    * Helper function that traces to the flashlog text file and also
    * displays output in the on-screen textfield console.
    */
    protected function consoleWrite(s:String):void
    {
      trace(s)
      if(enableConsole) {
        _tf.appendText(s)
        _tf.scrollV = _tf.maxScrollV
      }
    }

    public function sndComplete(e:Event):void
    {
      sndChan.removeEventListener(Event.SOUND_COMPLETE, sndComplete);
      sndChan = snd.play();
      sndChan.addEventListener(Event.SOUND_COMPLETE, sndComplete);
    }

    public function sndData(e:SampleDataEvent):void
    {
      e.data.length = 0
      sndDataBuffer = e.data

      if(frameCount == 0)
        return;

      if(engineticksoundptr == 0)
        engineticksoundptr = CModule.getPublicSymbol("engineTickSound")

      if(engineticksoundptr)
        CModule.callI(engineticksoundptr, emptyArgs)
    }

    /**
    * The enterFrame callback will be run once every frame. UI thunk requests should be handled
    * here by calling CModule.serviceUIRequests() (see CModule ASdocs for more information on the UI thunking functionality).
    */
    protected function enterFrame(e:Event):void
    {
        // Background worker handles blitting
        //try { C_Run.threadArbCondNotifyAll(); } catch(e:*) { Telemetry.sendMetric("threadArbCondNotifyAll FAILED", "true"); }
        CModule.serviceUIRequests();
        if(vbuffer == 0)
          vbuffer = CModule.getPublicSymbol("__avm2_vgl_argb_buffer")

     // } else {
     //   CModule.write32(vgl_mx, mx)
     //   CModule.write32(vgl_my, my)
     //   CModule.callI(enginetickptr, emptyArgs)
     // }

      ram.position = CModule.read32(vbuffer)
      if (ram.position != 0) {
        frameCount++
        bmd.setPixels(bmr, ram)
      }

      /*if(!snd)
      {
        snd = new Sound();
        snd.addEventListener( SampleDataEvent.SAMPLE_DATA, sndData );
      }
      if (!sndChan)
      {
        sndChan = snd.play();
        sndChan.addEventListener(Event.SOUND_COMPLETE, sndComplete);
      }*/
    }

    /**
    * Provide a way to get the TextField's text.
    */
    public function get consoleText():String
    {
        var txt:String = null;

        if(_tf != null){
            txt = _tf.text;
        }
        
        return txt;
    }
  }
}
