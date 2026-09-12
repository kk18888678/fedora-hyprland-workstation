import QtQuick

Item {
    function health(argument) {
        return argument === "{}" ? "healthy-service" : "healthy-service-unexpected-argument"
    }
}
