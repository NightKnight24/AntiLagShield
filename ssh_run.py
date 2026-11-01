import sys
import os
import pty
import select
import time

def run_ssh(user, host, password, command):
    pid, fd = pty.fork()
    if pid == 0:
        # Child process
        ssh_cmd = [
            "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR",
            f"{user}@{host}",
            command
        ]
        os.execvp("ssh", ssh_cmd)
    else:
        # Parent process
        output = []
        password_sent = False
        start_time = time.time()
        while time.time() - start_time < 20:
            r, _, _ = select.select([fd], [], [], 1)
            if fd in r:
                try:
                    data = os.read(fd, 1024)
                except OSError:
                    break
                if not data:
                    break
                output.append(data)
                combined = b"".join(output)
                if not password_sent and (b"Password" in combined or b"password" in combined):
                    time.sleep(0.1)
                    os.write(fd, password.encode() + b"\n")
                    password_sent = True
            elif password_sent:
                # If password was sent and no more output for 2 seconds, check if child exited
                pid_res, status = os.waitpid(pid, os.WNOHANG)
                if pid_res != 0:
                    break

        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.waitpid(pid, 0)
        except OSError:
            pass

        return b"".join(output).decode("utf-8", errors="replace")

if __name__ == "__main__":
    if len(sys.argv) < 5:
        print("Usage: python ssh_run.py <user> <host> <password> <command>")
        sys.exit(1)
    user, host, password, cmd = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    res = run_ssh(user, host, password, cmd)
    print(res)
