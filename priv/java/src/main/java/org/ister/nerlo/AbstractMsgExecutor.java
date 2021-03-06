package org.ister.nerlo;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Callable;

import org.ister.ej.Msg;
import org.ister.ej.MsgTag;

import com.ericsson.otp.erlang.OtpErlangPid;

/**
 *
 * @author ingo
 *
 */
public abstract class AbstractMsgExecutor implements Callable<Msg> {

	protected OtpErlangPid self = null;

	private Msg msg = null;

	public final Msg exec(Msg msg) {
		if (!checkMsg(msg)) {
			return errorAnswer(msg, "malformed_or_incomplete_message");
		}

		try {
			return execMsg(msg);
		} catch (ExecutorException e) {
			return errorAnswer(msg, e.getMessage());
		}
	}

	public final void setMsg(Msg msg) {
		this.msg = msg;
	}

	public final Msg call() {
		return exec(this.msg);
	}

	public void init(OtpErlangPid self) {
		this.self = self;
	}

	protected abstract String getId();

	protected abstract boolean checkMsg(Msg msg);

	protected abstract Msg execMsg(Msg msg) throws ExecutorException;

	private Msg errorAnswer(Msg msg, String reason) {
		Map<String, Object> map = new HashMap<String, Object>(2);
		map.put("reason", reason);
		return Msg.answer(self, MsgTag.ERROR, map, msg);
	}

}
