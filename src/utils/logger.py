import logging
import sys


def get_logger(name: str = "tastetrend", level: int = logging.INFO) -> logging.Logger:
    """
    Return a configured logger with consistent formatting.

    Args:
        name (str): Logger name (usually __name__ from caller).
        level (int): Logging level (default = INFO).

    Returns:
        logging.Logger: Configured logger instance.
    """
    logger = logging.getLogger(name)

    if not logger.handlers:
        # StreamHandler -> stdout (for Lambda/containers)
        handler = logging.StreamHandler(sys.stdout)
        formatter = logging.Formatter(
            fmt="[%(levelname)s] %(asctime)s %(name)s: %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )
        handler.setFormatter(formatter)
        logger.addHandler(handler)

    logger.setLevel(level)
    logger.propagate = False  # Avoid double logs in Lambda
    return logger
