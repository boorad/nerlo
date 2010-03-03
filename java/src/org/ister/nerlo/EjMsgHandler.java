package org.ister.nerlo;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.apache.log4j.Logger;
import org.ister.ej.AbstractMsgHandler;
import org.ister.ej.Main;
import org.ister.ej.Msg;
import org.ister.ej.MsgTag;
import org.ister.ej.Node;
import org.ister.nerlo.example.SimpleFiber;

/**
 * 
 * @author ingo
 *
 */
public class EjMsgHandler extends AbstractMsgHandler {

	private final Logger log    = Main.getLogger();
	private final Bundle bundle = Bundle.getInstance();
	
	@Override
	public void handle(Msg msg) {
    	MsgTag tag = msg.getTag();
    	if (tag.equals(MsgTag.CALL)) {
	    	// {self(), {call, [{call, job}]}}    
    		if (msg.match("call", "job")) {
	            job(msg);
    		} else {
    			log.warn("unhandled message from " + msg.getFrom().toString() + ": " + msg.getMsg().toString());
    		}
    	} else {
    		log.warn("unhandled message from " + msg.getFrom().toString() + ": " + msg.getMsg().toString());
        }

	}
	
  @SuppressWarnings("unchecked")
  private void job(Msg msg) {
	  Node node = getNode();
      List<Long> l = bundle.parallelCopyRun(new SimpleFiber());
      for (Long res : l) {
          log.info("future returned: " + res);
      }
      Map<String, Object> map = new HashMap<String, Object>(2);
      map.put("job", "done");
      map.put("result", l.toString());
      Msg answer = Msg.factory(node.getSelf(), new MsgTag(MsgTag.OK), map);
      node.sendPeer(answer);
  }

	@Override
	public void shutdown() {
		this.bundle.shutdown();
	}

}