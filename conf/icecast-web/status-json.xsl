<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <!--
        /!\ /status-json.xsl is deprecated since 2.5.x. This file is kept for compatibility with 2.4.x only.
        Please migrate to /admin/publicstats and consider /admin/eventfeed.
        No future non-security tickets for this file will be accepted.
    -->

    <xsl:import href="xml2json.xslt"/>
    <xsl:output indent="no" omit-xml-declaration="yes" method="text" encoding="UTF-8" media-type="application/json"/>
    <xsl:strip-space elements="*"/>

    <!-- override imported transform variable to enable output -->
    <xsl:variable name="output">true</xsl:variable>

    <!-- hide certain nodes from all sources -->
    <xsl:template match="icestats/source/max_listeners"><xsl:if test="not(following-sibling::*)">"dummy":null}</xsl:if></xsl:template>
    <xsl:template match="icestats/source/public"><xsl:if test="not(following-sibling::*)">"dummy":null}</xsl:if></xsl:template>
    <xsl:template match="icestats/source/source_ip"><xsl:if test="not(following-sibling::*)">"dummy":null}</xsl:if></xsl:template>
    <xsl:template match="icestats/source/slow_listeners"><xsl:if test="not(following-sibling::*)">"dummy":null}</xsl:if></xsl:template>
    <xsl:template match="icestats/source/*[contains(name(), 'total_bytes')]"><xsl:if test="not(following-sibling::*)">"dummy":null}</xsl:if></xsl:template>
    <xsl:template match="icestats/source/user_agent" ><xsl:if test="not(following-sibling::*)">"dummy":null}</xsl:if></xsl:template>
    <xsl:template match="icestats/source/listener" ><xsl:if test="not(following-sibling::*)">"dummy":null}</xsl:if></xsl:template>

    <!-- hide certain global nodes -->
    <xsl:template match="icestats/sources"><xsl:if test="not(following-sibling::*)">"dummy":null}</xsl:if></xsl:template>
    <xsl:template match="icestats/clients"><xsl:if test="not(following-sibling::*)">"dummy":null}</xsl:if></xsl:template>
    <xsl:template match="icestats/stats"><xsl:if test="not(following-sibling::*)">"dummy":null}</xsl:if></xsl:template>
    <xsl:template match="icestats/listeners"><xsl:if test="not(following-sibling::*)">"dummy":null}</xsl:if></xsl:template>
    <xsl:template match="node()[contains(name(), 'connections')]"><xsl:if test="not(following-sibling::*)">"dummy":null}</xsl:if></xsl:template>

</xsl:stylesheet>
