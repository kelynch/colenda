<?xml version="1.0"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:exsl="http://exslt.org/common"
  xmlns:ex="http://exslt.org/dates-and-times"
  xmlns:sv="http://www.jcp.org/jcr/sv/1.0"
  xmlns:image="http://www.modeshape.org/images/1.0"
  xmlns:space="preserve"
  extension-element-prefixes="exsl ex">
  <xsl:variable name="uuid">
    <xsl:value-of select="/root/record/uuid" />
  </xsl:variable>
  <xsl:output method="xml" indent="yes"/>
  <xsl:preserve-space elements="sv:node sv:property sv:value"/>
    <xsl:template match="/root/record">
      <xsl:copy>
        <exsl:document method="xml" href="fedora.xml">
          <sv:node xmlns:premis="http://www.loc.gov/premis/rdf/v1#"
            xmlns:image="http://www.modeshape.org/images/1.0"
            xmlns:sv="http://www.jcp.org/jcr/sv/1.0"
            xmlns:test="info:fedora/test/"
            xmlns:nt="http://www.jcp.org/jcr/nt/1.0"
            xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#"
            xmlns:ns001="info:fedora/fedora-system:def/model#"
            xmlns:ns002="http://purl.org/dc/terms/"
            xmlns:ns003="http://pcdm.org/models#"
            xmlns:ns004="http://library.upenn.edu/pqc/ns/"
            xmlns:space="preserve"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:mode="http://www.modeshape.org/1.0"
            xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
            xmlns:fedora="http://fedora.info/definitions/v4/repository#"
            xmlns:jcr="http://www.jcp.org/jcr/1.0"
            xmlns:ebucore="http://www.ebu.ch/metadata/ontologies/ebucore/ebucore#"
            xmlns:ldp="http://www.w3.org/ns/ldp#"
            xmlns:xs="http://www.w3.org/2001/XMLSchema"
            xmlns:fedoraconfig="http://fedora.info/definitions/v4/config#"
            xmlns:mix="http://www.jcp.org/jcr/mix/1.0"
            xmlns:foaf="http://xmlns.com/foaf/0.1/"
            xmlns:dc="http://purl.org/dc/elements/1.1/">
            <xsl:attribute name="sv:name"><xsl:value-of select="translate(substring-after($uuid,'ark:/'),'/','-')" /></xsl:attribute>
          <sv:property sv:name="jcr:primaryType" sv:type="Name">
            <sv:value>nt:folder</sv:value>
          </sv:property>
          <sv:property sv:name="jcr:mixinTypes" sv:type="Name" sv:multiple="false">
            <sv:value>fedora:Container</sv:value>
            <sv:value>fedora:Resource</sv:value>
          </sv:property>
          <sv:property sv:name="jcr:lastModifiedBy" sv:type="String">
            <sv:value>bypassAdmin</sv:value>
          </sv:property>
          <sv:property sv:name="ns001:hasModel" sv:type="String" sv:multiple="false">
            <sv:value>PrintedWork</sv:value>
          </sv:property>
          <sv:property sv:name="jcr:createdBy" sv:type="String">
            <sv:value>bypassAdmin</sv:value>
          </sv:property>
          <sv:property sv:name="ns002:abstract" sv:type="String" sv:multiple="false">
            <xsl:apply-templates select="abstract" />
          </sv:property>
          <sv:property sv:name="ns002:coverage" sv:type="String" sv:multiple="false">
            <xsl:apply-templates select="coverage" />
          </sv:property>
          <sv:property sv:name="ns004:uniqueIdentifier" sv:type="String" sv:multiple="false">
            <sv:value><xsl:value-of select="$uuid" /></sv:value>
          </sv:property>
          <sv:property sv:name="ns002:identifier" sv:type="String" sv:multiple="false">
            <xsl:apply-templates select="identifier" />
          </sv:property>
          <sv:property sv:name="ns002:language" sv:type="String" sv:multiple="false">
            <xsl:apply-templates select="language" />
          </sv:property>
          <sv:property sv:name="ns002:subject" sv:type="String" sv:multiple="false">
            <xsl:apply-templates select="subject" />
          </sv:property>
          <sv:property sv:name="ns002:description" sv:type="String" sv:multiple="false">
            <xsl:apply-templates select="description" />
          </sv:property>
          <sv:property sv:name="ns002:type" sv:type="String" sv:multiple="false">
            <xsl:apply-templates select="item_type" />
          </sv:property>
          <sv:property sv:name="ns002:title" sv:type="String" sv:multiple="false">
            <xsl:apply-templates select="title" />
          </sv:property>
          <sv:property sv:name="ns002:date" sv:type="String" sv:multiple="false">
            <xsl:apply-templates select="date" />
          </sv:property>
          <sv:property sv:name="ns004:personalName" sv:type="String" sv:multiple="false">
            <xsl:apply-templates select="personal_name" />
          </sv:property>
          <sv:property sv:name="ns004:corporateName" sv:type="String" sv:multiple="false">
            <xsl:apply-templates select="corporate_name" />
          </sv:property>
          <sv:property sv:name="ns004:geographicSubject" sv:type="String" sv:multiple="false">
            <xsl:apply-templates select="geographic_subject" />
          </sv:property>
          <sv:property sv:name="ns004:collection" sv:type="String" sv:multiple="false">
            <xsl:apply-templates select="collection" />
          </sv:property>
          <xsl:apply-templates select="pages/page" />
          </sv:node>
        </exsl:document>
      </xsl:copy>
    </xsl:template>

    <xsl:template match="abstract">
      <sv:value><xsl:apply-templates /></sv:value>
    </xsl:template>

    <xsl:template match="coverage">
      <sv:value><xsl:apply-templates /></sv:value>
    </xsl:template>

    <xsl:template match="identifier">
      <sv:value><xsl:apply-templates /></sv:value>
    </xsl:template>

    <xsl:template match="item_type">
      <sv:value><xsl:apply-templates /></sv:value>
    </xsl:template>

    <xsl:template match="language">
      <sv:value><xsl:apply-templates /></sv:value>
    </xsl:template>

    <xsl:template match="collection">
      <sv:value><xsl:apply-templates /></sv:value>
    </xsl:template>

    <xsl:template match="subject">
      <sv:value><xsl:apply-templates /></sv:value>
    </xsl:template>

    <xsl:template match="personal_name">
      <sv:value><xsl:apply-templates /></sv:value>
    </xsl:template>

    <xsl:template match="corporate_name">
      <sv:value><xsl:apply-templates /></sv:value>
    </xsl:template>

    <xsl:template match="geographic_subject">
      <sv:value><xsl:apply-templates /></sv:value>
    </xsl:template>

    <xsl:template match="description">
      <sv:value><xsl:apply-templates /></sv:value>
    </xsl:template>

    <xsl:template match="file_list/file">
      <sv:value><xsl:apply-templates /></sv:value>
    </xsl:template>

    <xsl:template match="title">
      <sv:value><xsl:apply-templates /></sv:value>
    </xsl:template>

    <xsl:template match="date">
      <sv:value><xsl:apply-templates /></sv:value>
    </xsl:template>

    <xsl:template match="pages/page">
      <sv:node>
      <xsl:attribute name="sv:name">
        <xsl:value-of select="format-number(page_number, '00000')" />
      </xsl:attribute>
      <sv:property sv:name="jcr:primaryType" sv:type="Name">
        <sv:value>nt:folder</sv:value>
      </sv:property>
      <sv:property sv:name="jcr:mixinTypes" sv:type="Name" sv:multiple="false">
        <sv:value>fedora:Container</sv:value>
        <sv:value>fedora:Resource</sv:value>
      </sv:property>
      <sv:property sv:name="jcr:lastModifiedBy" sv:type="String">
        <sv:value>bypassAdmin</sv:value>
      </sv:property>
      <sv:property sv:name="ns001:hasModel" sv:type="String" sv:multiple="false">
        <sv:value>Image</sv:value>
      </sv:property>
      <sv:property sv:name="jcr:createdBy" sv:type="String">
        <sv:value>bypassAdmin</sv:value>
      </sv:property>
      <sv:property sv:name="ns004:uniqueIdentifier" sv:type="String" sv:multiple="false">
        <sv:value><xsl:value-of select="concat($uuid, '/', format-number(page_number, '00000'))" /></sv:value>
      </sv:property>
      <sv:property sv:name="ns002:identifier" sv:type="String" sv:multiple="false">
        <sv:value><xsl:value-of select="identifier" /></sv:value>
      </sv:property>
      <sv:property sv:name="ns004:fileName" sv:type="String" sv:multiple="false">
        <sv:value><xsl:value-of select="file_name" /></sv:value>
      </sv:property>
      <sv:property sv:name="ns004:pageNumber" sv:type="Long" sv:multiple="false">
        <sv:value><xsl:value-of select="page_number" /></sv:value>
      </sv:property>
      <sv:property sv:name="ns004:sequence" sv:type="Long" sv:multiple="false">
        <sv:value><xsl:value-of select="sequence" /></sv:value>
      </sv:property>
      <sv:property sv:name="ns004:readingDirection" sv:type="String" sv:multiple="false">
        <sv:value><xsl:value-of select="reading_direction" /></sv:value>
      </sv:property>
      <sv:property sv:name="ns004:side" sv:type="String" sv:multiple="false">
        <sv:value><xsl:value-of select="side" /></sv:value>
      </sv:property>
      <sv:property sv:name="ns004:tocEntry" sv:type="String" sv:multiple="false">
        <sv:value><xsl:value-of select="toc_entry" /></sv:value>
      </sv:property>
      <sv:property sv:name="ns004:pageText" sv:type="String" sv:multiple="false">
        <sv:value><xsl:value-of select="ocr_text" /></sv:value>
      </sv:property>
      <sv:property sv:name="ns002:type" sv:type="String" sv:multiple="false">
        <sv:value>Page</sv:value>
      </sv:property>
    </sv:node>
  </xsl:template>

</xsl:stylesheet>