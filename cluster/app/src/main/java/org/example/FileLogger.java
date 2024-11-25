package org.example;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.LoggerContext;
import ch.qos.logback.classic.encoder.PatternLayoutEncoder;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.FileAppender;

import java.io.File;
import java.nio.file.Path;
import java.nio.file.Paths;

public class FileLogger {
  private final Logger logger;

  public FileLogger(String logDir, int nodeId, int serviceId) {
    // Ensure log directory exists
    File directory = new File(logDir);
    if (!directory.exists()) {
      directory.mkdirs();
    }

    // Create path for log file
    String fileName = String.format("%d-%d.log", nodeId, serviceId);
    Path logPath = Paths.get(logDir, fileName);
    // System.out.println("logPath: " + logPath);

    this.logger = createFileLogger("heartbeat-" + fileName, logPath.toString());
  }

  private Logger createFileLogger(String loggerName, String filePath) {
    LoggerContext loggerContext = (LoggerContext) LoggerFactory.getILoggerFactory();

    // Create and configure the encoder
    PatternLayoutEncoder encoder = new PatternLayoutEncoder();
    encoder.setContext(loggerContext);
    encoder.setPattern("%d{HH:mm:ss.SSS} %-5level %msg%n");
    encoder.start();

    // Create and configure the appender
    FileAppender<ILoggingEvent> fileAppender = new FileAppender<>();
    fileAppender.setContext(loggerContext);
    fileAppender.setFile(filePath);
    fileAppender.setEncoder(encoder);
    fileAppender.start();

    // Get logger and add appender
    ch.qos.logback.classic.Logger logbackLogger = loggerContext.getLogger(loggerName);
    logbackLogger.setAdditive(false);
    logbackLogger.setLevel(Level.INFO);
    logbackLogger.addAppender(fileAppender);

    return logbackLogger;
  }

  public void info(String msg) {
    logger.info(msg);
  }

  public void info(String format, Object... arguments) {
    logger.info(format, arguments);
  }

  public void warn(String format, Object... arguments) {
    logger.warn(format, arguments);
  }
}