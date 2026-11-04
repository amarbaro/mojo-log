from mlog import Logger, Field, INFO

def main() raises:
    var log = Logger(INFO, True)        # JSON lines on stderr; Logger(INFO, False, "app.log") appends text to a file
    log.info("request done", Field("path", "/api/v1/items"), Field("ms", 12.5), Field("n", 3), Field("ok", True))
    log.begin(4, "any number of fields")  # begin / field / end for a field list built at run time
    for i in range(3):
        log.field(Field("i", i))
    log.end()
