/// Only Windows asks the system for a volume's space this way.
({int available, int total})? windowsDiskSpace(String path) => null;
